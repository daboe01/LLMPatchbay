# backend for PatchbayLLM
# 29.12.23 by daniel boehringer
# Copyright 2023, All rights reserved.
#

use Apache::Session::File;
use Mojolicious::Lite;
use Mojo::Pg;
use Data::Dumper;
use Mojo::File;
use Mojo::JSON qw(decode_json encode_json);
use Encode; # utf8 and friends
use Mojo::Template;
use Mojolicious::Plugin::ClientIP; # internet-filter
use Text::CSV;
use IO::String;

use lib '/Users/daboe01/src/LLMPatchbay';
use pdfgen;
use secrets;

no warnings 'uninitialized';

helper pg => sub { state $pg = Mojo::Pg->new('postgresql://postgres@aug-info-db/llm_patchbay') };

plugin 'ClientIP';

# turn browser cache off
hook after_dispatch => sub {
    my $tx = shift;
    my $e = Mojo::Date->new(time-100);
    $tx->res->headers->header(Expires => $e);
    $tx->res->headers->header('X-ARGOS-Routing' => '3036');
};

get '/LLM/client_ip' => sub
{
    my $self = shift;

    $self->render(text => $self->client_ip);
};

post '/LLM/run/:key' => [key=>qr/\d+/] => sub
{
    my $self    = shift;
    my $id      = $self->param('key');
    my $idinput = $self->param('idinput');

    # spare labels (8) when looking for the output block
    my $block = $self->pg->db->query('select blocks.id, type from blocks join blocks_catalogue on idblock =  blocks_catalogue.id where idproject = ? and outputs is null and type != 8', $id)->hash;
    my $result = $self->get_result_of_block_id($block->{id}, $idinput);

    # save to scratchpad (preserve old one)
    $self->pg->db->query('update blocks set auxfield = output_value where idproject = ? and idblock = 14',   $id);
    $self->pg->db->query('update blocks set output_value = ? where idproject = ? and idblock = 14', $result, $id);
    $self->pg->db->query('update blocks set auxfield = ? where id = ?', $result, $block->{id});

    $self->pg->db->insert('output_data', {content => $result, idinput => $idinput}) if $idinput =~/^\d+$/o;

    my $o = {result => $result, err => $DBI::errstr};

    $o->{download} = 1 if $block->{type} eq '14'; # DownloadMarkdown should trigger download from gui

    $self->render(json => $o);
};

# called get (secondary from DownloadDiff after post to LLM/run)
get '/LLM/run/:key' => [key=>qr/\d+/] => sub
{
    my $self      = shift;
    my $id        = $self->param('key');
    my $markdown  = TempFileNames::tempFileName('/tmp/llmpb', '.md');
    my $markdown2 = TempFileNames::tempFileName('/tmp/llmpb', '.md');
    my $latex     = TempFileNames::tempFileName('/tmp/llmpb', '.tex');
    my $latex2    = TempFileNames::tempFileName('/tmp/llmpb', '.tex');

    my $scratch = $self->pg->db->query('select output_value, auxfield from blocks join blocks_catalogue on idblock = blocks_catalogue.id where idproject = ? and type = 13', $id)->hash;
    my $block   = $self->pg->db->query('select output_value, auxfield from blocks join blocks_catalogue on idblock = blocks_catalogue.id where idproject = ? and type in (14)', $id)->hash;

    my $data;

    my $out = encode 'UTF-8', $scratch ? $scratch->{output_value} : $block->{auxfield};
    Mojo::File->new($markdown)->spurt($out);
    system("/usr/local/bin/pandoc -s $markdown -o $latex");

    my $settings = $block->{output_value} ? decode_json($block->{output_value}) : {};

    if ($scratch && $scratch->{auxfield} && $settings->{perform_diff})
    {
        Mojo::File->new($markdown2)->spurt($scratch->{auxfield});
        system("/usr/local/bin/pandoc -s $markdown2 -o $latex2");

        warn Mojo::File->new($latex2)->slurp."__OLD_NEW_SEPARATOR__".Mojo::File->new($latex)->slurp;
        my $ua = Mojo::UserAgent->new;
        $data = $ua->post('http://aug-info.ukl.uni-freiburg.de:3018/BK/make_latex_track_changes' => {Accept => '*/*'} => Mojo::File->new($latex2)->slurp."__OLD_NEW_SEPARATOR__".Mojo::File->new($latex)->slurp)->res->body;
    }
    else
    {
        $data = pdfgen::PDFForTemplateAndRef(Mojo::File->new($latex)->slurp, {});
    }

    $self->render(data => $data, format => 'pdf');
};

#
# begin: generic DBI interface (CRUD)
#
# fetch all entities

get '/LLM/input_data'=> sub
{
    my $self    = shift;
    my $project = $self->param('project_id');

    $self->render(json => $self->pg->db->query(q{select id, case when length(content) > 2000 then left(content, 2000) || '...' else content end as content, insertion_time, idproject, coalesce(title, left(content, 10) || '...') as title from input_data where idproject = ?}, $project)->hashes);
};

get '/LLM/:table'=> sub
{
    my $self    = shift;
    my $project = $self->param('project_id');
    my $table   = $self->param('table');


    if ($table eq 'blocks')
    {
        $self->render(json => $self->pg->db->select($table, [qw/*/], {idproject => $project})->hashes);
        return;
    }
    elsif ($table eq 'blocks_catalogue' && $self->client_ip eq '193.196.199.168') # zugriff aus dem internet -> pot. gefaehrliche blocks sperren
    {
        $self->render(json => $self->pg->db->select($table, [qw/*/], {block_from_external => 0})->hashes);
        return;
    }

    $self->render(json => $self->pg->db->select($table, [qw/*/])->hashes);
};

# fetch entities by key/value

get '/LLM/settings/id/:key' => [key => qr/[a-z0-9\s\-_\.]+/i] => sub
{
    my $self = shift;
    my $id = $self->param('key');
    my $block = $self->pg->db->query(q{select output_value, gui_fields from blocks join blocks_catalogue on idblock = blocks_catalogue.id where blocks.id = ?}, $id)->hash;
    $block->{output_value} = '{}' unless $block->{output_value};

    my $out = $block->{gui_fields} ? decode_json($block->{output_value}) : {};
    $out->{id} = $id;
    $self->render(json => [$out]);
};

put '/LLM/settings/id/:key' => [key => qr/[a-z0-9\s\-_\.]+/i] => sub
{
    my $self = shift;
    my $id = $self->param('key');
    my $block = $self->pg->db->query(q{select output_value, gui_fields from blocks join blocks_catalogue on idblock = blocks_catalogue.id where blocks.id = ?}, $id)->hash;
    $block->{output_value} = '{}' unless $block->{output_value};
    my $out = decode_json($block->{output_value});
    my $patch = $self->req->json;

    foreach my $key (keys %{$patch})
    {
        $out->{$key} = $patch->{$key};
    }

    $self->pg->db->update('blocks', {output_value => encode_json $out}, {id => $id});
    $self->render(json => {err => $DBI::errstr});
};

get '/LLM/:table/:col/:key' => [col => qr/[a-z_0-9\s]+/i, key => qr/[a-z0-9\s\-_\.]+/i] => sub
{
    my $self = shift;
    $self->render(json => $self->pg->db->select($self->param('table'), [qw/*/], {$self->param('col') => $self->param('key')})->hashes);
};

# update
put '/LLM/:table/:pk/:key'=> [key => qr/\d+/] => sub
{
    my $self    = shift;
    $self->pg->db->update($self->param('table'), $self->req->json, {$self->param('pk') => $self->param('key')});
    $self->render(json => {err => $DBI::errstr});
};

# insert
post '/LLM/:table/:pk'=> sub
{
    my $self    = shift;
    my $project = $self->param('project_id');
    my $table   = $self->param('table');
    my $u       = $self->req->json;

    $project = 0 if $project eq 'undefined';

    $u->{idproject} = $project if $table eq 'blocks' || $table eq 'input_data';

    $u->{content} = 'Content goes here...' if !$u->{content} && $table eq 'input_data';

    my $id = $self->pg->db->insert($table, $u, {returning => $self->param('pk')})->hash->{id};

    $self->render(json => {err => $DBI::errstr, pk => $id});
};
# delete
del '/LLM/:table/:pk/:key' => [key=>qr/\d+/] => sub
{   my $self    = shift;
    my $id      = $self->param('key');
    my $table   = $self->param('table');
    $self->pg->db->delete($table, {$self->param('pk') => $id});

    $self->render(json => {err => $DBI::errstr});
};
#
# end: generic DBI interface
#

helper prepare_llm_prompt => sub { my ($self, $input, $prompt_template) = @_;
    my $prompt = $prompt_template;

    if ($prompt_template =~ /_INPUT_/so)
    {
        $prompt =~ s/_INPUT_/$input/so;
    }
    elsif ($input && $prompt_template)
    {
        $prompt = "$input $prompt_template";
    }
    else
    {
        $prompt = $prompt_template ? $prompt_template : $input;
    }

    return $prompt;
};

helper get_result_of_block_id => sub { my ($self, $id, $idinput) = @_;
    my $current_block = $self->pg->db->query('select type, connections, output_value from blocks join blocks_catalogue on idblock =  blocks_catalogue.id where blocks.id = ?', $id)->hash;
    my $conn = $current_block->{connections} ? decode_json $current_block->{connections} : {};
    my $inputs = {};
    my $result = '';

    # switch has to be valuated lazily
    if ($current_block->{type} ne '16')
    {
        foreach my $key (keys %{$conn})
        {
            $inputs->{$key} = $self->get_result_of_block_id($conn->{$key}, $idinput);
        }
    }

    if ($current_block->{type} eq '2') # LLM_Claude
    {
        my $prompt = $self->prepare_llm_prompt($inputs->{Input}, $inputs->{PromptTemplate});
        my $ua = Mojo::UserAgent->new;
        $ua->insecure(1); # keine zertifikats-validation
        $ua->inactivity_timeout(0);
        $ua->connect_timeout(0);

        my $settings = $current_block->{output_value} ? decode_json($current_block->{output_value}) : {};
        my $max_tokens = $settings->{max_tokens} || 20000;
        my $temperature = $settings->{temperature} || 0.1;
        my $version = $settings->{version} || 'claude-2';

        my $tx = $ua->post('https://api.anthropic.com/v1/complete' => {
            'x-api-key' => $secrets::claude_api_key,
            'content-type' => 'application/json'} => json => {
                # Send the prompt in the 'prompt' parameter
                prompt => "\n\nHuman: $prompt\n\nAssistant:",
                model => $version, max_tokens_to_sample => $max_tokens + 0, temperature => $temperature + 0.0, stop_sequences => ["\n\nHuman:"]

            });

        my $res = $tx->result;
        if ($res->is_success)
        {
            return $res->json->{completion};
        }

        return undef;
    }
    elsif ($current_block->{type} eq '15') # LLM_GPT4
    {
        my $prompt = $self->prepare_llm_prompt($inputs->{Input}, $inputs->{PromptTemplate});
        my $ua = Mojo::UserAgent->new;
        $ua->insecure(1); # keine zertifikats-validation
        $ua->inactivity_timeout(0);
        $ua->connect_timeout(0);

        my $settings = $current_block->{output_value} ? decode_json($current_block->{output_value}) : {};
        my $params =    {
                            model => 'gpt-4-1106-preview',
                            messages => [  {  role => "user", content => $prompt }  ]
                        };
        $ua->on(start => sub {
            my ($ua, $tx) = @_;
            $tx->req->headers->authorization("Bearer $secrets::openai_api_key");
        });

        return $ua->post("https://api.openai.com/v1/chat/completions" => json => $params)->res->json->{choices}->[0]->{message}->{content};
    }
    elsif ($current_block->{type} eq '9' || $current_block->{type} eq '10') # Llama-family
    {
        my $prompt = $self->prepare_llm_prompt($inputs->{Input}, $inputs->{PromptTemplate});
        my $ua = Mojo::UserAgent->new;
        $ua->insecure(1); # keine zertifikats-validation
        $ua->inactivity_timeout(0);
        $ua->connect_timeout(0);
        
        my $settings = $current_block->{output_value} ? decode_json($current_block->{output_value}) : {};
        my $model = $current_block->{type} eq '9' ? 'llama-2-70b-chat' : 'em-german-llama-2-70b';
        my $uri = 'http://aug-info.ukl.uni-freiburg.de:3018/BK/run_llm?model='.$model;
        $uri .= '&system_prompt='.$inputs->{SystemPrompt} if $inputs->{SystemPrompt};
        $uri .= '&max_tokens='.$settings->{max_tokens}    if $settings->{max_tokens};
        $uri .= '&nongreedy=1'                            if $settings->{is_nongreedy};

        return encode 'UTF-8', $ua->post($uri => json => { prompt => $prompt } )->res->body;
    }
    elsif ($current_block->{type} eq '1' || $current_block->{type} eq '13') # Text constant
    {
        return $current_block->{output_value};
    }
    elsif ($current_block->{type} eq '4' || $current_block->{type} eq '14') # growl / Download
    {
        return $inputs->{'Input'};
    }
    elsif ($current_block->{type} eq '5') # sprintf
    {
        return sprintf($current_block->{output_value}, $inputs->{Input});
    }
    elsif ($current_block->{type} eq '6') # sprintf2
    {
        return sprintf($current_block->{output_value}, $inputs->{Input1},  $inputs->{Input2});
    }
    elsif ($current_block->{type} eq '7') # sprintf3
    {
        return sprintf($current_block->{output_value}, $inputs->{Input1},  $inputs->{Input2},  $inputs->{Input3});
    }
    elsif ($current_block->{type} eq '19') # sprintf4
    {
        return sprintf($current_block->{output_value}, $inputs->{Input1},  $inputs->{Input2},  $inputs->{Input3},  $inputs->{Input4});
    }
    elsif ($current_block->{type} eq '20') # sprintf5
    {
        return sprintf($current_block->{output_value}, $inputs->{Input1},  $inputs->{Input2},  $inputs->{Input3},  $inputs->{Input4}, $inputs->{Input5});
    }
    elsif ($current_block->{type} eq '12') # http get
    {
        my $ua = Mojo::UserAgent->new;
        $ua->insecure(1); # keine zertifikats-validation
        $ua->inactivity_timeout(0);
        $ua->connect_timeout(0);
        my $uri = $current_block->{output_value};
        return decode 'UTF-8', $ua->get($uri)->res->body;
    }
    elsif ($current_block->{type} eq '11') # http post
    {
        my $ua = Mojo::UserAgent->new;
        $ua->insecure(1); # keine zertifikats-validation
        $ua->inactivity_timeout(0);
        $ua->connect_timeout(0);
        $ua->post($inputs->{URI} => {Accept => '*/*'} => $inputs->{Body});
    }
    elsif ($current_block->{type} eq '3') # regexp-extract
    {
        return $1 if $inputs->{'Input'} =~/$current_block->{output_value}/s;
        return undef;
    }
    elsif ($current_block->{type} eq '16') # switch->lazy evaluation
    {
        my $settings = $current_block->{output_value} ? decode_json($current_block->{output_value}) : {};
        return $self->get_result_of_block_id($conn->{$settings->{state} eq '1' ? 'Input2' : 'Input1'}, $idinput);
    }
    elsif ($current_block->{type} eq '17') # input
    {
        return decode 'UTF-8', $self->req->body unless $idinput =~/^\d+$/o;
        return $self->pg->db->query(q{select content from input_data where id = ?}, $idinput)->hash->{content};
    }
    elsif ($current_block->{type} eq '18') # json-processor
    {
        my $template = $current_block->{output_value};
        $template =~s/\binput\[['"]([^'"]+)['"]\]/ <%=  \$input->{$1}%> /g; # support 'nice' python-like syntax to access hashes
        return Mojo::Template->new->vars(1)->render($template, {input => decode_json(encode 'UTF-8', $inputs->{'Input'})});
    }

    return $result;
};

any '/LLM/revert_scratchpad/:key' => [key=>qr/\d+/] => sub
{
    my $self    = shift;
    my $id      = $self->param('key');

    $self->pg->db->query('update blocks set output_value = auxfield where idproject = ? and idblock = 14 and auxfield is not null', $id);

    $self->render(text => 'OK');
};


# fixme: all data are copied over, but all connections are broken.
any '/LLM/duplicate/:key' => [key=>qr/\d+/] => sub
{
    my $self        = shift;
    my $id          = $self->param('key');
    my $new_project = $self->pg->db->query('select max(idproject) as idproject from blocks')->hash->{idproject} + 1;

    $self->pg->db->query('select * from blocks where idproject = ?', $id)->hashes->each(sub{
        delete $_->{id};
        $_->{idproject} = $new_project;
        $self->pg->db->insert('blocks', $_);
    });
    $self->pg->db->query('select * from input_data where idproject = ?', $id)->hashes->each(sub{
        delete $_->{id};
        $_->{idproject} = $new_project;
        $self->pg->db->insert('input_data', $_);
    });

    $self->render(text => $new_project);
};

get '/LLM/csv/:key' => [key=>qr/\d+/] => sub
{
    my $self        = shift;
    my $id          = $self->param('key');

    my $hashes =  $self->pg->db->query(q{
                                            with last_generate as (
                                                SELECT max(id) as id, idinput
                                                FROM public.output_data group by  idinput)
                                            select input_data.title, output_data.idinput, output_data.content, output_data.insertion_time  from output_data join last_generate on last_generate.id=output_data.id
                                            join input_data on input_data.id=output_data.idinput where input_data.idproject=?

                                          }, $id)->hashes;

    # Assuming you have the first row to get the keys
    my $firstrow = decode_json $hashes->[0]->{content};
    my @keys = keys %{$firstrow};

    # Create a CSV string
    my $csv_string = '';
    my $io = IO::String->new($csv_string);

    # Create a CSV object
    my $csv = Text::CSV->new({ eol => "\n" });

    # Print header
    $csv->print($io, [(qw/id title insertion_time/, @keys)]);

    # Print data
    foreach my $row (@$hashes) {
        $csv->print($io, [$row->{idinput}, $row->{title}, $row->{insertion_time}, map { (decode_json $row->{content})->{$_} } @keys]);
    }

    $self->render(text => $csv_string, format => 'csv');
};

###################################################################
# main()

app->config(hypnotoad => {listen => ['http://*:3037'], workers => 2, heartbeat_timeout => 12000, inactivity_timeout => 12000});

app->start;
