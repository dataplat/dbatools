#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Shows an interactive WPF tree of databases and returns the one the user selects. Port of
/// public/Show-DbaDbList.ps1; the workflow remains a module-scoped PowerShell compatibility hop.
///
/// This is a THREE-BLOCK port (begin/process/end) with cross-block state, ported per the coordinator
/// ruling of 2026-07-18 19:18. Three carry mechanics, each deliberate:
///
/// (1) HELPER RELOCATION. The source defines two helpers in begin. Convert-b64toimg is both defined
/// and CALLED in begin, so it stays in the begin script. Add-TreeItem is defined in begin but CALLED
/// FROM PROCESS, and a function defined in one InvokeScoped call does not survive into another - so
/// it is relocated verbatim into the process script, which is where its only caller lives. Its body
/// is unchanged; it still closes over $DefaultDb and $dbicon and still writes $script:selected.
///
/// (2) ICON CARRY. Add-TreeItem needs $dbicon, and the process body needs $foldericon and
/// $dbatoolsicon, all three built in begin by Convert-b64toimg. They ride a state sentinel from the
/// begin script into C# fields and are passed back into the process script as ordinary arguments.
///
/// (3) CROSS-BLOCK RESULT STATE. $script:selected and $script:okay are written during process (by
/// Add-TreeItem, by the OK/Cancel click handlers, and by the TreeView SelectedEvent handler, all of
/// which run inside ShowDialog) and are READ IN END. Rather than lean on incidental module-scope
/// persistence between invocations, the process script emits them on a sentinel after ShowDialog
/// returns; C# holds them and passes them into the end script, whose condition is otherwise the
/// source's verbatim.
///
/// The begin Add-Type guard sets the interrupt latch that the source's process block reads via
/// Test-FunctionInterrupt; that latch is carried explicitly as _interrupted so the C# skips process
/// and end exactly as the source short-circuits.
///
/// SOURCE QUIRK PRESERVED VERBATIM: Add-TreeItem is called with -Tag $nameSpace, and $nameSpace is
/// never assigned anywhere in this command, so the tag is $null today. Shipped as-is; parity forbids
/// inventing a value. Likewise the Set-Variable -Scope Script pass that materialises $treeview,
/// $okbutton and $cancelbutton is carried unchanged.
///
/// COVERAGE HONESTY: the existing tests exercise only the two short-circuit guards (WPF-unavailable,
/// which is skipped on Windows, and connect-failure). The interactive ShowDialog half - including all
/// three carry mechanics above - is UNVERIFIED-BY-GATE. Per the ruling this row seals only as
/// SEALED-PENDING-MANUAL-UI until one human-driven dialog session confirms it, batched with the
/// TA-056 manual-UI backlog.
///
/// Surface pinned by migration/baselines/Show-DbaDbList.json.
/// </summary>
[Cmdlet(VerbsCommon.Show, "DbaDbList")]
public sealed class ShowDbaDbListCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance.</summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 0)]
    public DbaInstanceParameter? SqlInstance { get; set; }

    /// <summary>Login to the target instance using alternative credentials.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>The window title.</summary>
    [Parameter(Position = 2)]
    public string Title { get; set; } = "Select Database";

    /// <summary>The prompt shown above the tree.</summary>
    [Parameter(Position = 3)]
    public string Header { get; set; } = "Select the database:";

    /// <summary>The database pre-selected when the dialog opens.</summary>
    [Parameter(Position = 4)]
    public string? DefaultDb { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    private object? _dbicon;
    private object? _foldericon;
    private object? _dbatoolsicon;
    private bool _interrupted;
    private object? _selected;
    private object? _okay;

    protected override void BeginProcessing()
    {
        if (Interrupted)
            return;

        foreach (PSObject? item in NestedCommand.InvokeScoped(this, BeginScript,
            EnableException.ToBool(), NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug")))
        {
            if (item?.BaseObject is Hashtable sentinel && sentinel.ContainsKey("__showDbaDbListBegin"))
            {
                if (sentinel["__showDbaDbListBegin"] is Hashtable state)
                {
                    _dbicon = state["DbIcon"];
                    _foldericon = state["FolderIcon"];
                    _dbatoolsicon = state["DbatoolsIcon"];
                    _interrupted = LanguagePrimitives.IsTrue(state["Interrupted"]);
                }
                continue;
            }
            if (item?.BaseObject is ErrorRecord nestedError)
            {
                NestedCommand.RemoveDuplicateError(this, nestedError);
                WriteError(NestedCommand.PreserveErrorIdentity(nestedError));
                continue;
            }
            WriteObject(item);
        }
    }

    protected override void ProcessRecord()
    {
        if (Interrupted || _interrupted)
            return;

        foreach (PSObject? item in NestedCommand.InvokeScoped(this, ProcessScript,
            SqlInstance, SqlCredential, Title, Header, DefaultDb,
            _dbicon, _foldericon, _dbatoolsicon, EnableException.ToBool(),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug")))
        {
            if (item?.BaseObject is Hashtable sentinel && sentinel.ContainsKey("__showDbaDbListProcess"))
            {
                if (sentinel["__showDbaDbListProcess"] is Hashtable state)
                {
                    _selected = state["Selected"];
                    _okay = state["Okay"];
                }
                continue;
            }
            if (item?.BaseObject is ErrorRecord nestedError)
            {
                NestedCommand.RemoveDuplicateError(this, nestedError);
                WriteError(NestedCommand.PreserveErrorIdentity(nestedError));
                continue;
            }
            WriteObject(item);
        }
    }

    protected override void EndProcessing()
    {
        if (Interrupted || _interrupted)
            return;

        foreach (PSObject? item in NestedCommand.InvokeScoped(this, EndScript,
            _selected, _okay, EnableException.ToBool(),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug")))
        {
            if (item?.BaseObject is ErrorRecord nestedError)
            {
                NestedCommand.RemoveDuplicateError(this, nestedError);
                WriteError(NestedCommand.PreserveErrorIdentity(nestedError));
                continue;
            }
            WriteObject(item);
        }
    }

    // PS: the begin block. Convert-b64toimg stays here (it is defined AND called here); the three
    // icons it builds, plus the interrupt latch set by the Add-Type guard, ride out on a sentinel.
    // Add-TreeItem is NOT defined here - it moved to the process script, where its only caller is.
    // Edit: -FunctionName Show-DbaDbList on the Stop-Function.
    private const string BeginScript = """
param($EnableException, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    param($EnableException, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

    try {
        Add-Type -AssemblyName PresentationFramework
    } catch {
        Stop-Function -Message "Windows Presentation Framework required but not installed" -FunctionName Show-DbaDbList
        @{ __showDbaDbListBegin = @{ DbIcon = $null; FolderIcon = $null; DbatoolsIcon = $null; Interrupted = $true } }
        return
    }

    function Convert-b64toimg {
        param ($base64)

        $bitmap = New-Object System.Windows.Media.Imaging.BitmapImage
        $bitmap.BeginInit()
        $bitmap.StreamSource = [System.IO.MemoryStream][System.Convert]::FromBase64String($base64)
        $bitmap.EndInit()
        $bitmap.Freeze()
        return $bitmap
    }

    $dbicon = Convert-b64toimg "iVBORw0KGgoAAAANSUhEUgAAABQAAAAUCAYAAACNiR0NAAAAAXNSR0IArs4c6QAAAARnQU1BAACxjwv8YQUAAAAJcEhZcwAADsMAAA7DAcdvqGQAAAAYdEVYdFNvZnR3YXJlAHBhaW50Lm5ldCA0LjAuNWWFMmUAAAFRSURBVDhPY/j//z9VMVZBSjCCgQZunFn6/8zenv+7llf83zA75/+6WTn/N80v+L93ddP/M/tnY2jAayDIoNvn5/5/cX/t/89vdv7/9fUQGIPYj2+t/H/xyJT/O1ZUoWjCaeCOxcX///48ShSeWhMC14jXwC9Xs/5/fzHr/6/PW+GaQS78/WH9/y+Pe8DyT3fYEmcgKJw+HHECawJp/vZ60f8v95v/fzgd8P/tVtn/L1cw/n+0iOH/7TlMxBkIigBiDewr9iVsICg2qWrg6qnpA2dgW5YrYQOX9icPAQPfU9PA2S2RRLuwMtaGOAOf73X+//FyGl4DL03jIM5AEFjdH/x//+Lo/1cOlP9/dnMq2MA3x/z/312l/P/4JNH/axoU/0/INUHRhNdAEDi+pQ1cZIFcDEpvoPCaVOTwf1Gjy/9ds5MxNGAYSC2MVZB8/J8BAGcHwqQBNWHRAAAAAElFTkSuQmCC"
    $foldericon = Convert-b64toimg "iVBORw0KGgoAAAANSUhEUgAAABQAAAAUCAYAAACNiR0NAAAAAXNSR0IArs4c6QAAAARnQU1BAACxjwv8YQUAAAAJcEhZcwAADsMAAA7DAcdvqGQAAAAYdEVYdFNvZnR3YXJlAHBhaW50Lm5ldCA0LjAuNWWFMmUAAAHaSURBVDhPY/j//z9VMVZBSjBWQUowVkFKMApnzZL+/+gYWZ4YDGeANL95sun/j3fbwPjbm5X/Pz+cRLKhcAayq2B45YKe/8vndoHx4lltYLxgajMKhumHYRQDf37Yh4J/fNny//fb1f9/v1n6/8/Tqf//3O/6/+dO9f9fV4v+fzmV/v/L0aj/lflJQO1YDAS5AmwI1MvfPyAZ9KgbYtDlvP/fzyT9/3w45P+HPT7/z8+UwG0gyDvIBmIYBnQVyDCQq0CGPV9p8v94P/f/rKQwoHYsBs4HhgfIQJjLfr+YjdOwt5tt/z9eov1/fxf3/+ggD6B2HAaCXQYKM6hhv+81oYQXzLCXq03/P5qn/H9LE/9/LycroHYsBs7oq4EYCDIM6FVshr3Z4gg2DOS6O9Nk/q+sFvlvZawD1I7FwKldleC0h2zY9wuZEMP2+aMYdn+W/P/rE0T/zy+T+q+jJg/UjsXASe1l/z/cX/T/1dn8/492ePy/vc7s/82VOv8vLVT9f3yGwv89ffL/1zXL/l9dJwF2GciwaYVy/xVlxIDasRjY31Lyv7Uy+39ZTvz/1JiA/8Hejv8dLA3+62sqgTWJC/HixDAzQBjOoBbGKkgJxipICcYqSD7+zwAAkIiWzSGuSg0AAAAASUVORK5CYII="
    $dbatoolsicon = Convert-b64toimg "iVBORw0KGgoAAAANSUhEUgAAABkAAAAZCAYAAADE6YVjAAAAAXNSR0IArs4c6QAAAARnQU1BAACxjwv8YQUAAAAJcEhZcwAADsMAAA7DAcdvqGQAAAAYdEVYdFNvZnR3YXJlAHBhaW50Lm5ldCA0LjAuNWWFMmUAAAO9SURBVEhL3VVdTFNXHO9MzPTF+OzDeBixFdTMINIWsAUK3AIVkFvAIQVFRLYZKR8Wi1IEKV9DYB8PGFAyEx8QScySabYY5+I2JvK18iWISKGk0JGhLzA3+e2c29uHtpcvH/0lv9yennN+v3vO/3fOFb2fCAg4vXWPNOmMRJ745TtTSskqeElviGXJ0XtkWvjJkyGLPoFAVQZoe/NkX/n6Mh/ysu4Qy7WZdJAutxRW6zT6LcNQaE4LiGgREH4cibpCMNqzCIk9hbScEoSSZ0zKOa7fRxG/k5d1h8ukvO4a5ubmMT1jw5E0vZcBZWzqOTS3dcB8tRXZeRX4/v5DZH5uIu0Wrn8NEzaNDjgYoUPd120oMjViX2iql8H6ZFd8DzE7eFl3iOWpuyQydlh44kbJroilSd8RuQ+cqh7wC9Z+JJaxY8KTN0gp+5Yk9DaREzYhb5FOBwZFZ6LlZifKa5ux//AxYTHCvSEp8A9O5n77B6dwqXS119guZ+GrGq9jfn4eM7ZZxB/PdxN2UfOpHq3kRWq/uoE8Yx3u/fQLzhSYUdN0g+tfN126z0oxNj6BJz0Dq0b4E2UawuJzuPhKyZmKYr/AocgMrk37VzWRBLGRdE/psuXqk9wkT/GNUCJLWqS3By/rDh9FxjaSrnahiZ7cq8wCUzKImLIJqC+Ngbk4gmjjIKKKB6Aq7l+OLBmfVF0YnlQZR1p4eSd2y5IiyEr+oyJ0CwIi0gUNKAOPmnG04Q0utf+DHweWkFjjQOyVWajLpsCUPkeUcRgqAzE09Dfz8k64aqI9YcDziUk87bMgOCZL0CQ0ux2J9UtIbXyFwall/PD0NeLKrU6DkhGymj8RXtRDjU7x8k64TKpJQmi6bLOzSEgv8DYhNWMujiK+9jU0VQs4Vm/H2MwSOh4vcP+rii2cQVh+F+IqbRJe3glyReuoSFBUJtpu3eWulv2h3ueE1iOu0g5N9QL3jLk8jerbdrz59y1yGoYQUdSLsII/CLscIsD9UPrLUz4myXhBhWjCPMVdPBBnhMbsIAZzSDDbcOvRIhyLy6i4+Qyq82QFxECR9xjK/K5OXtodNHo+CsW2tagunbxADbK+sXP16Bv/G7lNQ8hpHEX21UGoDb/j8NmfoSzoNvCymwdTPvMotsKGB32LaL1H0mS0oOHOFLpH/0L3iAOF3/YSk4dgTBMh/JTNgdVbtzNl1il12UuSpHE+SRayTb0IL3yCMP2vUJKtUuh/szNNK8Jfxw3BZNpiMoGjiKPJm54Ffw8gEv0PQRYX7wDAUKEAAAAASUVORK5CYII="

    @{ __showDbaDbListBegin = @{ DbIcon = $dbicon; FolderIcon = $foldericon; DbatoolsIcon = $dbatoolsicon; Interrupted = $false } }
} $EnableException $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";

    // PS: the process block. Add-TreeItem is relocated here verbatim from the source's begin block
    // (its only caller is this block, and a function defined in the begin invocation would not
    // survive into this one). The three icons arrive as carried arguments. After ShowDialog returns,
    // $script:selected / $script:okay are emitted on a sentinel so the end block can read them
    // without relying on module-scope persistence across invocations.
    // Edits: -FunctionName Show-DbaDbList on the Stop-Function; the helper relocation; the sentinel emit.
    private const string ProcessScript = """
param($SqlInstance, $SqlCredential, $Title, $Header, $DefaultDb, $dbicon, $foldericon, $dbatoolsicon, $EnableException, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter]$SqlInstance, [PSCredential]$SqlCredential, [string]$Title, [string]$Header, [string]$DefaultDb, $dbicon, $foldericon, $dbatoolsicon, $EnableException, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

    function Add-TreeItem {
        param (
            [string]$name,
            [object]$parent,
            [string]$tag
        )

        $childitem = New-Object System.Windows.Controls.TreeViewItem
        $textblock = New-Object System.Windows.Controls.TextBlock
        $textblock.Margin = "5,0"
        $stackpanel = New-Object System.Windows.Controls.StackPanel
        $stackpanel.Orientation = "Horizontal"
        $image = New-Object System.Windows.Controls.Image
        $image.Height = 20
        $image.Width = 20
        $image.Stretch = "Fill"
        $image.Source = $dbicon
        $textblock.Text = $name
        $childitem.Tag = $name

        if ($name -eq $DefaultDb) {
            $childitem.IsSelected = $true
            $script:selected = $name
        }

        [void]$stackpanel.Children.Add($image)
        [void]$stackpanel.Children.Add($textblock)

        $childitem.Header = $stackpanel
        [void]$parent.Items.Add($childitem)
    }

    try {
        $server = Connect-DbaInstance -SqlInstance $SqlInstance -SqlCredential $SqlCredential
    } catch {
        Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $SqlInstance -FunctionName Show-DbaDbList
        return
    }

    # Create XAML form in Visual Studio, ensuring the ListView looks chromeless
    [xml]$xaml = "<Window
        xmlns='http://schemas.microsoft.com/winfx/2006/xaml/presentation'
        xmlns:x='http://schemas.microsoft.com/winfx/2006/xaml'
        Title='$Title' SizeToContent='WidthAndHeight' Background='#F0F0F0'
        WindowStartupLocation='CenterScreen' MaxHeight='600'>
    <Grid>
        <TreeView Name='treeview' Height='Auto' Width='Auto' Background='#FFFFFF' BorderBrush='#FFFFFF' Foreground='#FFFFFF' Margin='11,36,11,79'/>
        <Label x:Name='label' Content='$header' HorizontalAlignment='Left' Margin='15,4,10,0' VerticalAlignment='Top'/>
        <StackPanel HorizontalAlignment='Right' Orientation='Horizontal' VerticalAlignment='Bottom' Margin='0,50,10,30'>
        <Button Name='okbutton' Content='OK'  Margin='0,0,0,0' Width='75'/>
        <Label Width='10'/>
        <Button Name='cancelbutton' Content='Cancel' Margin='0,0,0,0' Width='75'/>
    </StackPanel>
</Grid>
</Window>"
    #second pushes it down
    # Turn XAML into PowerShell objects
    $window = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $xaml))
    $window.icon = $dbatoolsicon

    $xaml.SelectNodes("//*[@Name]") | ForEach-Object { Set-Variable -Name ($_.Name) -Value $window.FindName($_.Name) -Scope Script }

    $childitem = New-Object System.Windows.Controls.TreeViewItem
    $textblock = New-Object System.Windows.Controls.TextBlock
    $textblock.Margin = "5,0"
    $stackpanel = New-Object System.Windows.Controls.StackPanel
    $stackpanel.Orientation = "Horizontal"
    $image = New-Object System.Windows.Controls.Image
    $image.Height = 20
    $image.Width = 20
    $image.Stretch = "Fill"
    $image.Source = $foldericon
    $textblock.Text = "Databases"
    $childitem.Tag = "Databases"
    $childitem.isExpanded = $true
    [void]$stackpanel.Children.Add($image)
    [void]$stackpanel.Children.Add($textblock)
    $childitem.Header = $stackpanel
    #Variable marked as unused by PSScriptAnalyzer
    $null = $treeview.Items.Add($childitem)

    try {
        $databases = $server.Databases.Name
    } catch {
        return
    }

    foreach ($database in $databases) {
        Add-TreeItem -Name $database -Parent $childitem -Tag $nameSpace
    }

    $okbutton.Add_Click( {
            $window.Close()
            $script:okay = $true
        })

    $cancelbutton.Add_Click( {
            $script:selected = $null
            $window.Close()
        })

    $window.Add_SourceInitialized( {
            [System.Windows.RoutedEventHandler]$Event = {
                if ($_.OriginalSource -is [System.Windows.Controls.TreeViewItem]) {
                    $script:selected = $_.OriginalSource.Tag
                }
            }
            $treeview.AddHandler([System.Windows.Controls.TreeViewItem]::SelectedEvent, $Event)
        })

    $null = $window.ShowDialog()

    @{ __showDbaDbListProcess = @{ Selected = $script:selected; Okay = $script:okay } }
} $SqlInstance $SqlCredential $Title $Header $DefaultDb $dbicon $foldericon $dbatoolsicon $EnableException $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";

    // PS: the end block. The source reads $script:selected / $script:okay; here those values arrive
    // as carried arguments from the process sentinel, so the condition and the returned value are
    // otherwise the source's verbatim.
    private const string EndScript = """
param($selected, $okay, $EnableException, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    param($selected, $okay, $EnableException, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

    if ($selected.length -gt 0 -and $okay -eq $true) {
        return $selected
    }
} $selected $okay $EnableException $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";
}
