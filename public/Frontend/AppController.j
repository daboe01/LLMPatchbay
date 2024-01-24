/*
 * Cappuccino frontend for PatchbayLLM
 *
 * Created by daboe01 on Dec, 29, 2023 by Daniel Boehringer.
 * Copyright 2023, All rights reserved.
 *
 * Todo: bind label to block data in AppController so no reload is necessary after setting label name
 *
 *
 */



/////////////////////////////////////////////////////////

HostURL=""
BaseURL=HostURL+"/";

/////////////////////////////////////////////////////////

@import <Foundation/CPObject.j>
@import <Renaissance/Renaissance.j>
@import "EFView.j"
@import "EFLaceView.j"
@import "TNGrowlCenter.j";
@import "TNGrowlView.j";

@implementation FSArrayController(baseReloadFix)

- (void)fullyReloadAsync
{
    var entity = self._entity;
    entity._pkcache = [];
    [entity._store fetchObjectsForURLRequest:[entity._store requestForAddressingAllObjectsInEntity:entity] inEntity:entity requestDelegate:self._contentObject];
}

@end

@implementation CGPTURLRequest : CPURLRequest

- (id)initWithURL:(CPURL)anURL cachePolicy:(CPURLRequestCachePolicy)aCachePolicy timeoutInterval:(CPTimeInterval)aTimeoutInterval
{
    if (self = [super initWithURL:anURL initWithURL:anURL cachePolicy:aCachePolicy timeoutInterval:aTimeoutInterval])
    {
        [self setValue:"3037" forHTTPHeaderField:"X-ARGOS-ROUTING"];
    }

    return self;
}

@end

@implementation SessionStore : FSStore 

- (CPURLRequest)requestForAddressingObjectsWithKey: aKey equallingValue: (id) someval inEntity:(FSEntity) someEntity
{
    var request = [CGPTURLRequest requestWithURL: [self baseURL]+"/"+[someEntity name]+"/"+aKey+"/"+someval+"?project_id=" + window.G_PROJECT];

    return request;
}
-(CPURLRequest) requestForInsertingObjectInEntity:(FSEntity) someEntity
{
    var request = [CPURLRequest requestWithURL: [self baseURL]+"/"+[someEntity name]+"/"+ [someEntity pk]+"?project_id=" + window.G_PROJECT];
    [request setHTTPMethod:"POST"];

    return request;
}

- (CPURLRequest)requestForFuzzilyAddressingObjectsWithKey: aKey equallingValue: (id) someval inEntity:(FSEntity) someEntity
{
    var request = [CGPTURLRequest requestWithURL: [self baseURL]+"/"+[someEntity name]+"/"+aKey+"/like/"+someval+"?project_id=" + window.G_PROJECT];

    return request;
}

- (CPURLRequest)requestForAddressingAllObjectsInEntity:(FSEntity) someEntity
{
    var request = [CGPTURLRequest requestWithURL: [self baseURL]+"/"+[someEntity name]+"?project_id=" + window.G_PROJECT ];

    return request;
}

@end

@implementation GSMarkupTagPatchbayView: GSMarkupTagView

+ (Class) platformObjectClass
{
    return [EFLaceView class];
}
@end

@implementation CPConservativeDictionary:CPDictionary
+ (CPArray)keysForNonBoundsProperties
{
    return [];
}

- (void)setValue:(id)aVal forKey:(CPString)aKey
{
    if ([self objectForKey:aKey] != aVal)
        [super setValue:aVal forKey:aKey];
}
- (BOOL)isEqual:(id)otherObject
{
    return [self valueForKey:'id'] == [otherObject valueForKey:'id'];
}
@end

@implementation CPArray(outletsContainer)
- (CPArray)allObjects
{
    return self;
}
@end

@implementation CPColor(BlendAddititon)
- (CPColor)blendedColorWithFraction:(CGFloat)fraction ofColor:(CPColor)color
{
    var red = [_components[0], color._components[0]],
        green = [_components[1], color._components[1]],
        blue = [_components[2], color._components[2]],
        alpha = [_components[3], color._components[3]];

    var blendedRed = red[0] + fraction * (red[1] - red[0]);
    var blendedGreen = green[0] + fraction * (green[1] - green[0]);
    var blendedBlue = blue[0] + fraction * (blue[1] - blue[0]);
    var blendedAlpha = alpha[0] + fraction * (alpha[1] - alpha[0]);

    return [CPColor colorWithCalibratedRed:blendedRed green:blendedGreen blue:blendedBlue alpha:blendedAlpha];
}
@end


@implementation AppController : CPObject
{
    id  store @accessors;

    id  mainWindow;
    id  addBlocksWindow;
    id  editWindow;
    id  laceView;
    id  inputWindow;
    id  inputText;

    id  inputController
    id  outputController
    id  blocksCatalogueController @accessors;
    id  blocksController @accessors;
    id  screenController @accessors;
    id  settingsController @accessors;
    id  blockIndex;
    id  connections;
    id  addBlocksPopover;
    id  editPopover;
    id  runConnection;
    id  spinnerImg;
    id _blockGUIConnector;
}

+ (void)connectBlock:(id)mydata toOtherBlock:(id)mydata2 usingOutletNamed:(CPString)name
{
    var startHoles = [mydata valueForKey:'outputs'];
    var endHoles = [mydata2 valueForKey:'inputs'];
    var myinput;

    if (!startHoles)
        return;

    for (var i = 0; i < [endHoles count] ; i++)
    {
        if ([endHoles[i] valueForKey:"label"] == name)
        {
            myinput = endHoles[i];
            break;
        }
    }

    if ([[startHoles[0] valueForKey:"laces"] isKindOfClass:CPArray])
        [startHoles[0] valueForKey:"laces"].push(myinput);
    else
        [startHoles[0] setValue:[myinput] forKey:"laces"];

    [myinput setValue:mydata2 forKey:"data"]
    [startHoles[0] setValue:mydata forKey:"data"]
}

- (void)laceView:(EFLaceView)aView didConnectHole:(id)startHole toHole:(id)endHole
{
    var sourcePK = [[startHole valueForKey:"data"] valueForKey:'id']
    var targetPK = [[endHole valueForKey:"data"] valueForKey:'id'];
    var outletName = [endHole valueForKey:"label"];
    var o = [blocksController._entity objectWithPK:targetPK];
    var connString = [o valueForKey:'connections'];
    var conn = connString ? JSON.parse([o valueForKey:'connections']) : {};
    conn[outletName] = sourcePK;
    [o setValue:JSON.stringify(conn) forKey:"connections"];
}

- (void)laceView:(EFLaceView)aView didUnconnectHole:(id)startHole fromHole:(id)endHole
{
    var targetPK = [[endHole valueForKey:"data"] valueForKey:'id'];
    var outletName = [endHole valueForKey:"label"];
    var o = [blocksController._entity objectWithPK:targetPK];
    var connString = [o valueForKey:'connections'];

    var conn = connString ? JSON.parse([o valueForKey:'connections']) : {};
    delete conn[outletName];
    [o setValue:JSON.stringify(conn) forKey:"connections"];
}

- (void)laceView:(EFLaceView)aView showTooltipForHole:(id)aHole
{
    // FIXME
    // document.title = [aHole valueForKey:"label"]
}

- (void)laceView:(EFLaceView)aView didDragBlockView:(EFView)aView
{
    var data = [aView valueForKey:'data'];
    var point = [aView frame].origin;
    var o = [blocksController._entity objectWithPK:[data valueForKey:'id']];
    [o setValue:point.x forKey:"originX"];
    [o setValue:point.y forKey:"originY"];
}

- (void)cancelEdit:(id)sender
{
    [editPopover close];
}

- (CPString)_compileGUIXML:(CPString)string rotatedResultsPrefix:(CPString)rrprefix
{
    string = [string stringByReplacingOccurrencesOfString:'column="' withString:'valueBinding="#CPOwner.'+rrprefix+'.selection.'];

    return  '<?xml version="1.0"?> <!DOCTYPE gsmarkup>  <gsmarkup> <objects> <window visible="NO"> <vbox id="widgets">' + string +
    '</vbox> </window>  </objects> <connectors> <outlet source="#CPOwner" target="widgets" label="_blockGUIConnector"/> </connectors></gsmarkup>';
}

- (void)laceView:(EFLaceView)aView didDoubleClickView:(EFView)aView
{
    var effectiveView;
    var pk = [aView valueForKeyPath:'data.id'];
    [blocksController rearrangeObjects]
    [blocksController setFilterPredicate:[CPPredicate predicateWithFormat:"id = %@", pk + '']]
    [[blocksController selectedObject] reload];
    if (!editPopover)
    {
        editPopover = [CPPopover new];
        [editPopover setDelegate:self];
        [editPopover setAnimates:NO];
        [editPopover setBehavior:CPPopoverBehaviorTransient];
        [editPopover setAppearance:CPPopoverAppearanceMinimal];
    }

    var myViewController = [CPViewController new];
    [editPopover setContentViewController:myViewController];

    var gui_xml = [blocksController valueForKeyPath:"selection.block_type.gui_xml"];

    if ([gui_xml isKindOfClass:CPString])
    {
        gui_xml = [self _compileGUIXML:gui_xml rotatedResultsPrefix:'settingsController'];
        var cols = JSON.parse([blocksController valueForKeyPath:"selection.block_type.gui_fields"]);
        cols.push('id'); // primary key
        settingsController._entity._columns = [CPSet setWithArray:cols];
        [settingsController reload]

        [CPBundle loadGSMarkupData:[CPData dataWithRawString:gui_xml] externalNameTable:[CPDictionary dictionaryWithObject:self forKey:"CPOwner"] localizableStringsTable:nil inBundle:nil tagMapping:nil];

        var mysize = CGSizeMake(300, 600)
        var view = [[CPView alloc] initWithFrame:CGRectMake(0, 0, mysize.width, mysize.height)];
        [view setFrameSize:mysize];
        [view addSubview:_blockGUIConnector];

        effectiveView = view;
    }
    else
        effectiveView = [editWindow contentView];

    [myViewController setView:effectiveView];
    [editPopover showRelativeToRect:NULL ofView:aView preferredEdge:nil];
}

- (void)removeBlock:(id)sender
{
    var selectedBlocks = [screenController selectedObjects];

    // delete each block in backend separately
    for(var i = 0; i < [selectedBlocks count]; i++)
    {
        var dbo = [blocksController._entity objectWithPK:[selectedBlocks[i] valueForKey:'id']];
        [blocksController._entity deleteObject:dbo];
    }

    // delete all selected blocks in frontend at once
    [laceView delete:self];
}

- (void)performAddBlocks:(id)sender
{
    var selectedBlocks = [blocksCatalogueController selectedObjects];
    var currentX = 0;
    var currentY = 0;

    for(var i = 0; i < [selectedBlocks count]; i++)
    {
        var currentBlockTemplate = selectedBlocks[i];
        var mydata = [CPConservativeDictionary new];
        [mydata setValue:currentX forKey:'originX'];
        [mydata setValue:currentY forKey:'originY'];
        [mydata setValue:[currentBlockTemplate valueForKey:'id'] forKey:'idblock'];
        [mydata setValue:[currentBlockTemplate valueForKey:'default_value'] forKey:'output_value'];
        var dbo = [blocksController._entity createObjectWithDictionary:mydata];
        [blocksController._entity insertObject:dbo];
        [blocksController fullyReloadAsync];
        [screenController insertObject:[self blockForData:dbo] atArrangedObjectIndex:0];

        currentX += 100;
    }

}

- (void)addBlocks:(id)sender
{
    if (!addBlocksPopover)
    {
        addBlocksPopover = [CPPopover new];
        [addBlocksPopover setDelegate:self];
        [addBlocksPopover setAnimates:NO];
        [addBlocksPopover setBehavior:CPPopoverBehaviorTransient];
        [addBlocksPopover setAppearance:CPPopoverAppearanceMinimal];
        var myViewController = [CPViewController new];
        [addBlocksPopover setContentViewController:myViewController];
        [myViewController setView:[addBlocksWindow contentView]];
    }

    [addBlocksPopover showRelativeToRect:NULL ofView:sender preferredEdge:nil];
}

- (void)cancelAddBlocks:(id)sender
{
    [addBlocksPopover close];
}

- (id)blockForData:(id)o
{
    var mydata = [CPConservativeDictionary new];
    var title = [o valueForKeyPath:"block_type.name"];

    var x    = parseInt([o valueForKey:'originX'], 10)
    var y    = parseInt([o valueForKey:'originY'], 10)
    var myid = parseInt([o valueForKey:'id'], 10)

    x = isNaN(x) ? 0 : x;
    y = isNaN(y) ? 0 : y;
    [mydata setValue:x forKey:'originX'];
    [mydata setValue:y forKey:'originY'];
    [mydata setValue:myid forKey:'id'];

    if (title == 'Label')
    {
        mydata.is_label = YES;
        [mydata setValue:[o valueForKey:'output_value']  || 'Label' forKey:'title'];
    }
    else
        [mydata setValue:title forKey:'title'];

    var connString = [o valueForKey:'connections'];

    if (connString)
    {
        var conn = JSON.parse(connString);
        conn['target'] = myid;
        connections.push(conn);
    }

    var myinputArray = [];
    var conncatString = [o valueForKeyPath:'block_type.inputs'];

    if (conncatString)
    {
        var conncat = JSON.parse(conncatString);

        for (var j = 0 ; j < conncat.length ; j++)
        {
            var myinput = @{'label': conncat[j]};
            myinputArray.push(myinput);
        }
    }

    [mydata setValue:myinputArray forKey:'inputs'];

    var myoutputArray = [];
    var conncatStringOut = [o valueForKeyPath:'block_type.outputs'];

    if (conncatStringOut)
    {
        var conncat = JSON.parse(conncatStringOut);
        for (var j = 0 ; j < conncat.length ; j++)
        {
            var effectiveLabel = conncat[j] == 'Output' ? '↣' : conncat[j];
            var myoutput = @{'label': effectiveLabel};
            myoutputArray.push(myoutput);
        }
    }

    [mydata setValue:myoutputArray forKey:'outputs'];

    [blockIndex setObject:mydata forKey:myid];

    return mydata;
}

- (void)setupBlocksView
{
    var blocks = [blocksController arrangedObjects];

    connections = [];

    blockIndex = @{};

    for (var i = 0 ; i < [blocks count] ; i++)
    {
        var o = blocks[i];

        var mydata = [self blockForData:o];
        [screenController insertObject:mydata atArrangedObjectIndex:0];
    }

    for (var i = 0 ; i < connections.length ; i++)
    {
        var conn = connections[i];

        var target = [blockIndex objectForKey:conn['target']];

        for (var key in conn)
        {
            if (conn.hasOwnProperty(key))
            {
                if (key == 'target')
                    continue;

                var source = [blockIndex objectForKey:conn[key]];
                [AppController connectBlock:source toOtherBlock:target usingOutletNamed:key]
            }
        }
    }
}

-(void)setButtonBusy:(CPButton)myButton
{
    myButton._oldImage = [myButton image];
    [myButton setImage:spinnerImg];
    [myButton setValue:spinnerImg forThemeAttribute:@"image" inState:CPThemeStateDisabled];
    [myButton setEnabled:NO];
}
-(void)resetButtonBusy:(CPButton)myButton
{
    [myButton setImage:myButton._oldImage];
    [myButton setEnabled:YES];
}

- (void)run:(id)sender
{
    var myreq = [CPURLRequest requestWithURL:"/LLM/run/" + window.G_PROJECT + "?idinput=" + [inputController valueForKeyPath:"selection.id"]
                                 cachePolicy:CPURLRequestReloadIgnoringLocalCacheData timeoutInterval:500000];
    [myreq setHTTPMethod:"POST"];
    runConnection = [CPURLConnection connectionWithRequest:myreq delegate:self];

    [self setButtonBusy:sender]
    runConnection._senderButton = sender;
}

- (void)revertScratchpad:(id)sender
{
    var myreq = [CPURLRequest requestWithURL:"/LLM/revert_scratchpad/" + window.G_PROJECT];
    [CPURLConnection connectionWithRequest:myreq delegate:nil];
}

- (void)insertInput:(id)sender
{
    [inputController insert:sender]
    [inputWindow makeKeyAndOrderFront:sender]
    [inputText selectAll:sender]
}

- (void)removeInput:(id)sender
{
    [inputController remove:sender]
}

- (void)downloadOutput:(id)sender
{
    window.open("/LLM/output_data/id/" + [outputController valueForKeyPath:"selection.id"], 'download_window');
}

- (void)connection:(CPConnection)someConnection didReceiveData:(CPData)data
{
    if (someConnection._senderButton && [someConnection._senderButton isKindOfClass:CPButton])
        [self resetButtonBusy:someConnection._senderButton];

    var result = JSON.parse(data);

    if (result['download'])
        window.open("/LLM/run/" + window.G_PROJECT + "?idinput=" + [inputController valueForKeyPath:"selection.id"] , 'download_window');
    else
        [[TNGrowlCenter defaultCenter] pushNotificationWithTitle:"Result" message:result['result'] customIcon:TNGrowlIconInfo];

    [outputController reload];
}

- (void)applicationDidFinishLaunching:(CPNotification)aNotification
{
    store = [[SessionStore alloc] initWithBaseURL:HostURL+"/LLM"];

    var re = new RegExp("project=([0-9]+)");
    var m = re.exec(document.location);

    if(m)
        window.G_PROJECT = m[1];

    [CPBundle loadRessourceNamed:"model.gsmarkup" owner:self];
    [CPBundle loadRessourceNamed:"gui.gsmarkup" owner:self];
    spinnerImg = [[CPImage alloc] initWithContentsOfFile:[CPString stringWithFormat:@"%@%@", [[CPBundle mainBundle] resourcePath], "spinner.gif"]];

    var contentView = [mainWindow contentView];
    [contentView setBackgroundColor:[CPColor colorWithWhite:0.95 alpha:1.0]];

    [[TNGrowlCenter defaultCenter] setView:[[CPApp mainWindow] contentView]];
    [[TNGrowlCenter defaultCenter] setLifeDefaultTime:10];

    screenController = [CPArrayController new];

    [self setupBlocksView];

    [laceView bind:"selectionIndexes" toObject:screenController withKeyPath:"selectionIndexes" options:nil]
    [laceView bind:"dataObjects"      toObject:screenController withKeyPath:"arrangedObjects" options:nil]
    [laceView setDelegate:self];

    // document.title = [[CPURLConnection sendSynchronousRequest:[CPURLRequest requestWithURL:"/LLM/client_ip"] returningResponse: nil] rawString];
}

@end
