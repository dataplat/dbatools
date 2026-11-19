#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Imports Extended Events session templates (bundled or from files) onto SQL Server instances, optionally
/// rewriting the event_file target path.
/// </summary>
/// <remarks>
/// The instance connection, the template resolution, the XML target-path rewriting, the
/// CreateSessionFromTemplate call, and the resulting Get-DbaXESession all run the original dbatools
/// PowerShell body VERBATIM inside the dbatools module scope rather than being reimplemented in C#, so the
/// engine decides the observable details.
///
/// The command processes and emits PER RECORD (unlike a purely end-block command), so the process body runs
/// in a per-record hop during ProcessRecord - preserving pipeline streaming (records received before an
/// upstream terminating failure are processed) and evaluating each Test-Bound at the record it belongs to.
/// The begin block's $metadata (Import-Clixml of the bundled metadata under $script:PSModuleRoot) is a
/// once-only value carried from BeginProcessing.
///
/// The source keeps its process locals on the FUNCTION scope, so a value assigned in one record is still
/// visible in the next when a Stop-Function -Continue skips the reassignment (stale $server, $xml,
/// $basename, $tempfile) or a parameter is mutated ($Name, $TargetFilePath, $TargetFileMetadataPath - the
/// last two via a non-idempotent "TrimEnd both separators then append one"). A fresh per-record hop scope
/// would lose that, so those locals are seeded from a carried state at the top of each record's hop and
/// re-emitted through a sentinel (rode out on a finally so an early return still carries them). Every
/// Test-Bound becomes a carried immutable flag ($__pathBound, $__templateBound, $__nameBound,
/// $__targetFilePathBound, $__targetFileMetadataPathBound), sampled per record (Test-Bound never rides the
/// hop). No process block reads Test-FunctionInterrupt, so no interrupt is carried. Each created session
/// emits before a later file or instance may fail under -EnableException, so the hop uses
/// InvokeScopedStreaming. Surface pinned by migration/baselines/Import-DbaXESessionTemplate.json.
/// </remarks>
[Cmdlet(VerbsData.Import, "DbaXESessionTemplate")]
public sealed class ImportDbaXESessionTemplateCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 0)]
    [PsDbaInstanceArrayCast]
    public DbaInstanceParameter[] SqlInstance { get; set; } = null!;

    /// <summary>Login to the target instance using alternative credentials.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>The name for the imported session.</summary>
    [Parameter(Position = 2)]
    public string? Name { get; set; }

    /// <summary>The path(s) to template file(s) to import.</summary>
    [Parameter(ValueFromPipelineByPropertyName = true, Position = 3)]
    [Alias("FullName")]
    public string[]? Path { get; set; }

    /// <summary>The bundled template name(s) to import.</summary>
    [Parameter(Position = 4)]
    public string[]? Template { get; set; }

    /// <summary>Rewrite the event_file target to this path.</summary>
    [Parameter(Position = 5)]
    public string? TargetFilePath { get; set; }

    /// <summary>Rewrite the event_file metadata target to this path.</summary>
    [Parameter(Position = 6)]
    public string? TargetFileMetadataPath { get; set; }

    /// <summary>Whether the imported session should start automatically.</summary>
    [Parameter(Position = 7)]
    [PsStringCast]
    [ValidateSet("On", "Off")]
    public string StartUpState { get; set; } = "Off";

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    // The bundled metadata, read once in the begin hop.
    private object? _metadata;

    // The source's function-scope process locals, carried record to record (see the class remarks). The
    // three mutated parameters seed from their bound values; the loop locals seed from null.
    private object? _name;
    private object? _targetFilePath;
    private object? _targetFileMetadataPath;
    private object? _server;
    private object? _store;
    private object? _xml;
    private object? _basename;
    private object? _tempfile;

    protected override void BeginProcessing()
    {
        _name = Name;
        _targetFilePath = TargetFilePath;
        _targetFileMetadataPath = TargetFileMetadataPath;

        foreach (PSObject? item in NestedCommand.InvokeScoped(this, BeginScript,
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug")))
        {
            if (item?.BaseObject is Hashtable sentinel && sentinel.ContainsKey("__importDbaXESessionTemplateBegin"))
            {
                if (sentinel["__importDbaXESessionTemplateBegin"] is Hashtable state)
                {
                    _metadata = state["Metadata"];
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
        NestedCommand.InvokeScopedStreaming(this, item =>
        {
            if (item?.BaseObject is Hashtable sentinel && sentinel.ContainsKey("__importDbaXESessionTemplateProcess"))
            {
                if (sentinel["__importDbaXESessionTemplateProcess"] is Hashtable state)
                {
                    _name = state["Name"];
                    _targetFilePath = state["TargetFilePath"];
                    _targetFileMetadataPath = state["TargetFileMetadataPath"];
                    _server = state["Server"];
                    _store = state["Store"];
                    _xml = state["Xml"];
                    _basename = state["Basename"];
                    _tempfile = state["Tempfile"];
                }
                return;
            }
            if (item?.BaseObject is ErrorRecord nestedError)
            {
                NestedCommand.RemoveDuplicateError(this, nestedError);
                WriteError(NestedCommand.PreserveErrorIdentity(nestedError));
            }
            else
            {
                WriteObject(item);
            }
        }, ProcessScript,
            SqlInstance, SqlCredential, Path, Template, StartUpState, _metadata, EnableException.ToBool(),
            _name, _targetFilePath, _targetFileMetadataPath, _server, _store, _xml, _basename, _tempfile,
            TestBound(nameof(Path)), TestBound(nameof(Template)), TestBound(nameof(Name)),
            TestBound(nameof(TargetFilePath)), TestBound(nameof(TargetFileMetadataPath)),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    // PS: the begin block VERBATIM ($script:PSModuleRoot resolves in the module scope), returning $metadata
    // via a sentinel. Runs once in BeginProcessing.
    private const string BeginScript = """
param($__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    $__moduleRoot = (Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1).ModuleBase
    $xmlpath = Join-DbaPath $__moduleRoot "bin" "xetemplates-metadata.xml"
    $metadata = Import-Clixml $xmlpath
    @{ __importDbaXESessionTemplateBegin = @{ Metadata = $metadata } }
} @__commonParameters 3>&1 2>&1
""";

    // PS: the process block VERBATIM apart from -FunctionName Import-DbaXESessionTemplate on the direct
    // Stop-Function/Write-Message sites, every Test-Bound -> the carried immutable flag, $metadata supplied
    // from the begin carry, and the function-scope process locals seeded from carried state and re-emitted
    // in a sentinel (on a finally). EnableException is bound so Stop-Function's scope-walking default inherits it.
    private const string ProcessScript = """
param($SqlInstance, $SqlCredential, $Path, $Template, $StartUpState, $metadata, $EnableException, $__carriedName, $__carriedTargetFilePath, $__carriedTargetFileMetadataPath, $__carriedServer, $__carriedStore, $__carriedXml, $__carriedBasename, $__carriedTempfile, $__pathBound, $__templateBound, $__nameBound, $__targetFilePathBound, $__targetFileMetadataPathBound, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, $SqlCredential, [string[]]$Path, [string[]]$Template, [string]$StartUpState, $metadata, $EnableException, $__carriedName, $__carriedTargetFilePath, $__carriedTargetFileMetadataPath, $__carriedServer, $__carriedStore, $__carriedXml, $__carriedBasename, $__carriedTempfile, $__pathBound, $__templateBound, $__nameBound, $__targetFilePathBound, $__targetFileMetadataPathBound)
    $__moduleRoot = (Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1).ModuleBase
    # Seed the carried cross-record function-scope locals (the source keeps them on the persistent scope).
    $Name = $__carriedName
    $TargetFilePath = $__carriedTargetFilePath
    $TargetFileMetadataPath = $__carriedTargetFileMetadataPath
    $server = $__carriedServer
    $store = $__carriedStore
    $xml = $__carriedXml
    $basename = $__carriedBasename
    $tempfile = $__carriedTempfile
    try {
    if ((-not $__pathBound) -and (-not $__templateBound)) {
        Stop-Function -Message "You must specify Path or Template." -FunctionName Import-DbaXESessionTemplate
    }

    if (($Path.Count -gt 1 -or $Template.Count -gt 1) -and ($__nameBound)) {
        Stop-Function -Message "Name cannot be specified with multiple files or templates because the Session will already exist." -FunctionName Import-DbaXESessionTemplate
        return
    }

    foreach ($instance in $SqlInstance) {
        try {
            $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 11
        } catch {
            Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue -FunctionName Import-DbaXESessionTemplate
        }

        $SqlConn = $server.ConnectionContext.SqlConnectionObject
        $SqlStoreConnection = New-Object Microsoft.SqlServer.Management.Sdk.Sfc.SqlStoreConnection $SqlConn
        $store = New-Object Microsoft.SqlServer.Management.XEvent.XEStore $SqlStoreConnection

        foreach ($file in $template) {
            $templatepath = Join-DbaPath $__moduleRoot "bin" "XEtemplates" "$file.xml"
            if ((Test-Path $templatepath)) {
                $Path += $templatepath
            } else {
                Stop-Function -Message "Invalid template ($templatepath does not exist)." -Continue -FunctionName Import-DbaXESessionTemplate
            }
        }

        foreach ($file in $Path) {

            if (-not $__targetFilePathBound) {
                Write-Message -Level Verbose -Message "Importing $file to $instance" -FunctionName Import-DbaXESessionTemplate -ModuleName "dbatools"
                try {
                    $xml = [xml](Get-Content $file -ErrorAction Stop)
                } catch {
                    Stop-Function -Message "Failure" -ErrorRecord $_ -Target $file -Continue -FunctionName Import-DbaXESessionTemplate
                }
            } else {
                Write-Message -Level Verbose -Message "TargetFilePath specified, changing all file locations in $file for $instance." -FunctionName Import-DbaXESessionTemplate -ModuleName "dbatools"

                # Handle whatever people specify
                $TargetFilePath = $TargetFilePath.TrimEnd("\").TrimEnd("/")
                if ($__targetFileMetadataPathBound) {
                    Write-Message -Level Verbose -Message "TargetFileMetadataPath specified, changing all metadata file locations in $file for $instance." -FunctionName Import-DbaXESessionTemplate -ModuleName "dbatools"
                    $TargetFileMetadataPath = $TargetFileMetadataPath.TrimEnd("\").TrimEnd("/")
                }
                if ((Test-HostOSLinux -SqlInstance $server)) {
                    $TargetFilePath = "$TargetFilePath/"
                    if ($__targetFileMetadataPathBound) {
                        $TargetFileMetadataPath = "$TargetFileMetadataPath/"
                    }
                } else {
                    $TargetFilePath = "$TargetFilePath\"
                    if ($__targetFileMetadataPathBound) {
                        $TargetFileMetadataPath = "$TargetFileMetadataPath\"
                    }
                }

                try {
                    $basename = (Get-ChildItem $file).Basename
                    $templateXml = [xml](Get-Content $file -Raw -ErrorAction Stop)
                    $namespaceUri = $templateXml.DocumentElement.NamespaceURI
                    $eventSessionNode = $templateXml.SelectSingleNode("/*[local-name()='event_sessions']/*[local-name()='event_session']")
                    if (-not $eventSessionNode) {
                        throw "No event_session element found in template $file."
                    }

                    $eventFileTargetNode = $eventSessionNode.SelectSingleNode("*[local-name()='target' and @name='event_file']")
                    $eventFileTargetExists = $null -ne $eventFileTargetNode

                    if (-not $eventFileTargetExists) {
                        # No event_file target found in template - add one so TargetFilePath is honored
                        Write-Message -Level Verbose -Message "No event_file target found in template, adding one with TargetFilePath." -FunctionName Import-DbaXESessionTemplate -ModuleName "dbatools"
                        $eventFileTargetNode = $templateXml.CreateElement("target", $namespaceUri)
                        $null = $eventFileTargetNode.SetAttribute("package", "package0")
                        $null = $eventFileTargetNode.SetAttribute("name", "event_file")
                    }

                    $filenameParameterNode = $eventFileTargetNode.SelectSingleNode("*[local-name()='parameter' and @name='filename']")
                    if (-not $filenameParameterNode) {
                        $filenameParameterNode = $templateXml.CreateElement("parameter", $namespaceUri)
                        $null = $filenameParameterNode.SetAttribute("name", "filename")
                        $null = $eventFileTargetNode.AppendChild($filenameParameterNode)
                    }

                    $filenameValue = $filenameParameterNode.GetAttribute("value")
                    if ([string]::IsNullOrWhiteSpace($filenameValue)) {
                        $filenameValue = $basename
                    }
                    $null = $filenameParameterNode.SetAttribute("value", "$TargetFilePath$filenameValue")

                    if ($__targetFileMetadataPathBound) {
                        $metadataParameterNode = $eventFileTargetNode.SelectSingleNode("*[local-name()='parameter' and @name='metadatafile']")
                        if ($metadataParameterNode) {
                            $metadataValue = $metadataParameterNode.GetAttribute("value")
                            if ([string]::IsNullOrWhiteSpace($metadataValue)) {
                                $metadataValue = $basename
                            }
                            $null = $metadataParameterNode.SetAttribute("value", "$TargetFileMetadataPath$metadataValue")
                        } elseif (-not $eventFileTargetExists) {
                            $metadataParameterNode = $templateXml.CreateElement("parameter", $namespaceUri)
                            $null = $metadataParameterNode.SetAttribute("name", "metadatafile")
                            $null = $metadataParameterNode.SetAttribute("value", "$TargetFileMetadataPath$basename")
                            $null = $eventFileTargetNode.AppendChild($metadataParameterNode)
                        }
                    }

                    if (-not $eventFileTargetExists) {
                        $null = $eventSessionNode.AppendChild($eventFileTargetNode)
                    }

                    $temp = ([System.IO.Path]::GetTempPath()).TrimEnd("").TrimEnd("\").TrimEnd("/")
                    $tempfile = Join-DbaPath $temp $basename
                    $null = Set-Content -Path $tempfile -Value $templateXml.OuterXml -Encoding UTF8
                    $xml = $templateXml
                    $file = $tempfile
                } catch {
                    Stop-Function -Message "Failure" -ErrorRecord $_ -Target $file -Continue -FunctionName Import-DbaXESessionTemplate
                }

                Write-Message -Level Verbose -Message "$TargetFilePath does not exist on $server, creating now." -FunctionName Import-DbaXESessionTemplate -ModuleName "dbatools"
                try {
                    if (-not (Test-DbaPath -SqlInstance $server -Path $TargetFilePath)) {
                        $null = New-DbaDirectory -SqlInstance $server -Path $TargetFilePath
                    }
                } catch {
                    Stop-Function -Message "Failure" -ErrorRecord $_ -Target $file -Continue -FunctionName Import-DbaXESessionTemplate
                }
            }

            if (-not $xml.event_sessions) {
                Stop-Function -Message "$file is not a valid XESession template document." -Continue -FunctionName Import-DbaXESessionTemplate
            }

            if ((-not $__nameBound)) {
                $Name = (Get-ChildItem $file).BaseName
            }

            # This could be done better but not today
            $no2012 = ($metadata | Where-Object Compatibility -gt 2012).Name
            $no2014 = ($metadata | Where-Object Compatibility -gt 2014).Name

            if ($Name -in $no2012 -and $server.VersionMajor -eq 11) {
                Stop-Function -Message "$Name is not supported in SQL Server 2012 ($server)" -Continue -FunctionName Import-DbaXESessionTemplate
            }

            if ($Name -in $no2014 -and $server.VersionMajor -eq 12) {
                Stop-Function -Message "$Name is not supported in SQL Server 2014 ($server)" -Continue -FunctionName Import-DbaXESessionTemplate
            }

            if ((Get-DbaXESession -SqlInstance $server -Session $Name)) {
                Stop-Function -Message "$Name already exists on $instance" -Continue -FunctionName Import-DbaXESessionTemplate
            }

            try {
                Write-Message -Level Verbose -Message "Importing $file as $Name" -FunctionName Import-DbaXESessionTemplate -ModuleName "dbatools"
                $session = $store.CreateSessionFromTemplate($Name, $file)
                $session.Create()
                if ($file -eq $tempfile) {
                    Remove-Item $tempfile -ErrorAction SilentlyContinue
                }
                if ($StartUpState -eq "On") {
                    $newsession = Get-DbaXESession -SqlInstance $server -Session $session.Name
                    if (-not $newsession.AutoStart) {
                        $newsession.AutoStart = $true
                        $newsession.Alter()
                    }
                    $newsession | Start-DbaXESession
                } else {
                    Get-DbaXESession -SqlInstance $server -Session $session.Name
                }
            } catch {
                Stop-Function -Message "Failure" -ErrorRecord $_ -Target $store -Continue -FunctionName Import-DbaXESessionTemplate
            }
        }
    }
    } finally {
        @{ __importDbaXESessionTemplateProcess = @{ Name = $Name; TargetFilePath = $TargetFilePath; TargetFileMetadataPath = $TargetFileMetadataPath; Server = $server; Store = $store; Xml = $xml; Basename = $basename; Tempfile = $tempfile } }
    }
} $SqlInstance $SqlCredential $Path $Template $StartUpState $metadata $EnableException $__carriedName $__carriedTargetFilePath $__carriedTargetFileMetadataPath $__carriedServer $__carriedStore $__carriedXml $__carriedBasename $__carriedTempfile $__pathBound $__templateBound $__nameBound $__targetFilePathBound $__targetFileMetadataPathBound @__commonParameters 3>&1 2>&1
""";
}
