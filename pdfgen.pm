#!/usr/bin/perl
use lib qw{/Users/Shared/bin/};	#mac/linux
use TempFileNames;
use Mojo::UserAgent;

# 11.5.05 by dr. boehringer

package pdfgen;

sub expandPDFDict { my ($block,$dict)=@_;
	foreach my $key (keys %{$dict})
	{	if( ref($dict->{$key}) eq 'ARRAY' )
		{	$block =~s/<foreach:$key\b([^>]*)>(.+?)<\/foreach:$key>/expandPDFForeachs ($2, $dict->{$key}, $1)/iegs;		# without workaround
		} else
		{	$dict->{$key} =~s/([<>])/ \$$1\$ /igs;
			$dict->{$key} =~s/(?<!\\)([_%&])/\\$1/gs unless $key =~/_RAW_/;
            $dict->{$key} =~s/"/''/gs;
			$block =~s/<\Q$key\E>/$dict->{$key}/iegs;
		} 
	} return $block;
}
sub expandPDFForeachs { my ($block,$arr, $sepStr)=@_;
	my $sep;
	$sep = $1 if($sepStr=~/sep=\"(.*?)\"/ois);
	my @ret=map { expandPDFDict($block,$_) } (@{$arr});
	@ret=grep { !/^\s*$/ } @ret;

	return join ($sep, @ret);
}

sub copyTexToTemp { my ($name, $objc)=@_;
    $name = expandPDFDict($name, $objc);
	warn $name;
    if($name =~/^http:/)
    {   my $data= Mojo::UserAgent->new->get($name)->res->body;
        my $tmpfilename=TempFileNames::tempFileName('/tmp/argos','.pdf');
        TempFileNames::writeFile($tmpfilename, $data);
        warn $name;
        $name=$tmpfilename;
    } else
    {   system("cp /Users/Shared/bin/ARGOS/forms/forms/$name /tmp/");
    }
	return $name;
}

sub PDFFilenameForTemplateAndRef { my ($str, $objc, $xe, $source, $run2)=@_;
	if(ref($objc) eq 'ARRAY')
			{	$str =~s/<foreach>(.*?)<\/foreach>/expandPDFForeachs($1,$objc)/oegs }
	else 	{	$str = expandPDFDict($str,$objc)}
	$str=~s/{copytex:([^}]+)}/copyTexToTemp($1, $objc)/oegs;
    $str=~s/<[a-z0-9_]{2,30}>//ogsi; # remove unmatched placeholders
    $str=~s/\xB0/\$^\\circ\$/ogsi; # gradzeichen hochgestellt
    $str=~s/\xB5/\$\\mu\$/ogsi; # micro
    $str=~s/\xE0/\\`{a}/ogsi; # a accent
    $str=~s/ß/\$\\beta\$/ogsi; # beta
    $str=~s/\^(\w+)/\$^$1\$/ogsi; # square
    $str=~s/\xB2/\$^2\$/ogsi; # square

    $str=~s/\s+\\vspace\{\d+mm\}\n+\s\{\\bf\s:\}/; /ogsi; # boeser hack fuer die stationaeren arztbriefe (oldstyle)
    $str=~s/\s+\\vspace\{\d+mm\}\n+\\noindent\s+\{\\bf\s:\}/; /ogsi; # boeser hack fuer die stationaeren arztbriefe (newstyle)
    $str=~s/}\s+[RL]A; /}/ogsi; # leerer befund in stationaeren arztbriefen
    $str=~s/\s+(LA\s+[0-9\.]+:)/\\\\$1/ogsi; # LA umbruch bei pentacam in stationaeren arztbriefen
    $str=~s/:}\s+(RA\s+[0-9\.]+:)/:}\\\\$1/ogsi; # RA umbruch bei pentacam in stationaeren arztbriefen

#printf ("%s %s\n", $_, unpack("H* ",$_)) for split /\n/, $str;
# warn $str;
    my $tmpfilename = TempFileNames::tempFileName('/tmp/clinical','');
	TempFileNames::writeFile($tmpfilename.'.tex', $str);

    return $tmpfilename.'.tex' if $source;

    $main::ENV{PATH} = '/usr/texbin'; 								#untaint
    my $binary=$xe? '/usr/texbin/xelatex' : '/usr/texbin/pdflatex';
    system('cd /tmp; export PATH="/usr/local/bin:$PATH"; '.$binary.' --interaction=batchmode  '.$tmpfilename.'.tex ');
#warn('cd /tmp; export PATH="/usr/local/bin:$PATH"; '.$binary.' --interaction=batchmode  '.$tmpfilename.'.tex ');
    system('cd /tmp; export PATH="/usr/local/bin:$PATH"; '.$binary.' --interaction=batchmode  '.$tmpfilename.'.tex ') if $run2;
    # system('cd /tmp; export PATH="/usr/local/bin:$PATH"; /usr/texbin/xelatex --interaction=batchmode '.$tmpfilename.'.tex ');
	return $tmpfilename.'.pdf';
}

sub PDFForTemplateAndRef { my ($str, $objc, $xe, $source, $run2)=@_;
	my $filename = PDFFilenameForTemplateAndRef($str,$objc, $xe, $source, $run2);
	my $data = TempFileNames::readFile($filename);
	return $data;
}

sub LPRPrint { my ($data, $printer, $copies, $options)=@_;
    $options = '' if $options =~/^\s+$/o;
	my $prn=$options?   "/usr/bin/ssh root\@augcupsserver /usr/bin/lpr -P $printer -# "."$copies -o $options <":
                        "/usr/bin/ssh root\@augcupsserver /usr/bin/lpr -P $printer -# "."$copies  <";
	my $tmpfilename= TempFileNames::tempFileName('/tmp/rpr2', '');
	TempFileNames::writeFile($tmpfilename, $data);
	system("scp /Users/Shared/bin/ARGOSAM/forms/textpos.sty root\@auginfo:/tmp/textpos.sty");
	system($prn.$tmpfilename);
	warn  ($prn.$tmpfilename);
}
sub applyDictToRTF { my ($dict,$rtf)=@_;
	while(my($key,$val)=each %{$dict} )
	{	$rtf =~s/\{\\\*\\bkmkstart $key\}\s*\{\\\*\\bkmkend $key\}/{\\*\\bkmkstart $key}{\\*\\bkmkend $key}${val}/gs; # traditional
    	$rtf =~s/\{\\\*\\bkmkstart $key\}[\s\.]+\{\\\*\\bkmkend $key\}/{\\*\\bkmkstart $key}${val}{\\*\\bkmkend $key}/gs # fuer das adressfeld und damit den medoc seriendruck
	}
	return Encode::encode('ascii', $rtf, sub{ sprintf "\\'%x", shift })
}

sub PDFTrackChanges { my ($old_source, $new_source) = @_;
    my $tmpfilename_old = TempFileNames::tempFileName('/tmp/clinical', '.tex');
    TempFileNames::writeFile($tmpfilename_old, $old_source);
    my $tmpfilename_new = TempFileNames::tempFileName('/tmp/clinical', '.tex');
    TempFileNames::writeFile($tmpfilename_new, $new_source);
    my $tmpfilename = TempFileNames::tempFileName('/tmp/clinical');
    system("/usr/local/bin/latexdiff $tmpfilename_old $tmpfilename_new >$tmpfilename.tex");

    $main::ENV{PATH} = '/usr/texbin';                                 #untaint
    my $binary = '/usr/texbin/pdflatex';
    system('cd /tmp; export PATH="/usr/local/bin:$PATH"; '.$binary.' --interaction=batchmode  '.$tmpfilename.'.tex ');
    return TempFileNames::readFile($tmpfilename.'.pdf');
}

1;
