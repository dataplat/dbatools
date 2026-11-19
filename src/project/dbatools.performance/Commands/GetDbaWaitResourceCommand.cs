#nullable enable

using System;
using System.Collections;
using System.Collections.ObjectModel;
using System.Management.Automation;
using System.Text.RegularExpressions;
using Dataplat.Dbatools.Connection;
using Dataplat.Dbatools.Parameter;
using Microsoft.SqlServer.Management.Smo;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Decodes a PAGE or KEY wait resource. Port of public/Get-DbaWaitResource.ps1 (W1-104).
/// The format gate (two case-insensitive -notmatch tests) Stop-Functions record-less and
/// returns; the connect catch targets the UNDEFINED $instance (module-then-global read)
/// and its -Continue sits OUTSIDE any loop - PS flow control STOPS the whole pipeline,
/// modeled with the _pipelineStopped flag; everything post-connect rides one VERBATIM
/// module hop per record (the $matches captures, the Databases ID lookup, the PAGE
/// branch with DBCC PAGE under try/Stop-Function and the Write-Message -Warning BINDING
/// BUG preserved, the KEY branch with the %%lockres%% row expansion and the lowercase
/// Objectname prop; in-hop Stop-Functions carry -FunctionName per the W1-090 law).
/// SqlInstance is a SINGLE DbaInstance and WaitResource pipes. Surface pinned by
/// migration/baselines/Get-DbaWaitResource.json.
/// </summary>
[Cmdlet(VerbsCommon.Get, "DbaWaitResource")]
public sealed class GetDbaWaitResourceCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance.</summary>
    [Parameter(Mandatory = true, Position = 0)]
    public DbaInstanceParameter SqlInstance { get; set; } = null!;

    /// <summary>Login to the target instance using alternative credentials.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>The wait resource string (PAGE: d:f:p or KEY: d:h (lockres)).</summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 2)]
    [PsStringCast]
    public string WaitResource { get; set; } = null!;

    /// <summary>Also fetches the locked row for KEY resources.</summary>
    [Parameter]
    public SwitchParameter Row { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    // PS: `continue` outside a loop in a process block STOPS the whole pipeline.
    private bool _pipelineStopped;

    protected override void ProcessRecord()
    {
        if (_pipelineStopped)
            return;

        // PS: the format gate - case-insensitive -notmatch pair.
        if (!Regex.IsMatch(WaitResource, "^PAGE: [0-9]*:[0-9]*:[0-9]*$", RegexOptions.IgnoreCase)
            && !Regex.IsMatch(WaitResource, "^KEY: [0-9]*:[0-9]* \\([a-f0-9]*\\)$", RegexOptions.IgnoreCase))
        {
            StopFunction("Row input - " + WaitResource + " - Improperly formatted");
            return;
        }

        Hashtable connectParams = new Hashtable();
        connectParams["SqlInstance"] = SqlInstance;
        connectParams["SqlCredential"] = SqlCredential;
        NestedConnect.Outcome connection = NestedConnect.Connect(this, connectParams);
        if (!connection.Ok)
        {
            // PS: -Target $instance reads the UNDEFINED variable (module-then-global);
            // -Continue outside a loop stops the WHOLE pipeline.
            object? target = ModuleVariableValue("instance");
            StopFunction("Failure", target: target, errorRecord: connection.Failure, category: ErrorCategory.ConnectionError, continueLoop: true);
            _pipelineStopped = true;
            return;
        }
        Server server = connection.Server!;

        // The whole post-connect body is VERBATIM; the only throw-through is the
        // EE Stop-Function (the function terminating path), which propagates.
        foreach (PSObject? item in NestedCommand.InvokeScoped(this, BodyScript, server, WaitResource, Row.ToBool(), EnableException.ToBool(), BoundVerbose(), BoundDebug()))
            WriteObject(item);
    }

    /// <summary>The undefined-variable read (module scope then global).</summary>
    private object? ModuleVariableValue(string name)
    {
        Collection<PSObject> results = NestedCommand.InvokeScoped(this, ModuleVariableScript, name);
        return results.Count == 1 ? results[0] : null;
    }

    /// <summary>A bound -Debug carrier for the hop scopes (W1-044 convention).</summary>
    private object? BoundDebug()
    {
        object? debug;
        if (MyInvocation.BoundParameters.TryGetValue("Debug", out debug))
            return LanguagePrimitives.IsTrue(debug);
        return null;
    }

    /// <summary>A bound -Verbose carrier for the hop scopes (W1-044 convention).</summary>
    private object? BoundVerbose()
    {
        object? verbose;
        if (MyInvocation.BoundParameters.TryGetValue("Verbose", out verbose))
            return LanguagePrimitives.IsTrue(verbose);
        return null;
    }

    private const string ModuleVariableScript = """
param($__name)
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    param($__name)
    $ExecutionContext.SessionState.PSVariable.GetValue($__name)
} $__name
""";

    // PS: the post-connect body VERBATIM (the $matches captures, the ID lookup, the
    // PAGE and KEY branches with their warnings/faults, the -Row expansion).
    private const string BodyScript = """
param($server, $WaitResource, $Row, $EnableException, $__boundVerbose, $__boundDebug)
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    param($server, $WaitResource, $Row, $EnableException, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundVerbose) { $VerbosePreference = $(if ($__boundVerbose) { "Continue" } else { "SilentlyContinue" }) }
    if ($null -ne $__boundDebug) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }
    $null = $WaitResource -match '^(?<Type>[A-Z]*): (?<dbid>[0-9]*):*'
    $resourceType = $matches.Type
    $dbId = $matches.DbId
    $dbName = ($server.Databases | Where-Object ID -eq $dbId).Name
    if ($null -eq $dbName) {
        stop-function -Message "Database with id $dbId does not exist on $server" -FunctionName Get-DbaWaitResource
        return
    }
    if ($resourceType -eq 'PAGE') {
        $null = $WaitResource -match '^(?<Type>[A-Z]*): (?<dbid>[0-9]*):(?<FileID>[0-9]*):(?<PageID>[0-9]*)$'
        $dataFileSql = "SELECT name, physical_name FROM sys.master_files WHERE database_id=$dbId AND file_ID=$($matches.FileID);"
        $dataFile = $server.query($dataFileSql)
        if ($null -eq $dataFile) {
            Write-Message -Level Warning -Message "Datafile with id $($matches.FileID) for $dbName not found"
            return
        }
        $objectIdSql = "DBCC TRACEON (3604); DBCC PAGE ($dbId,$($matches.fileID),$($matches.PageID),2) WITH TABLERESULTS;"
        try {
            $objectId = ($server.databases[$dbName].Query($objectIdSql) | Where-Object Field -eq 'Metadata: ObjectId').Value
        } catch {
            Stop-Function -Message "You've requested a page beyond the end of the database, exiting" -FunctionName Get-DbaWaitResource
            return
        }
        if ($null -eq $objectId) {
            Write-Message -Level Warning -Message "Object not found, could have been delete, or a transcription error when copying the Wait_resource to PowerShell"
            return
        }
        $objectSql = "SELECT SCHEMA_NAME(schema_id) AS SchemaName, name, type_desc FROM sys.all_objects WHERE object_id=$objectId;"
        $object = $server.databases[$dbName].query($objectSql)
        if ($null -eq $object) {
            Write-Message -Warning "Object could not be found. Could have been removed, or could be a transcription error copying the Wait_resource to sowerShell"
        }
        [PSCustomObject]@{
            DatabaseID   = $dbId
            DatabaseName = $dbName
            DataFileName = $dataFile.name
            DataFilePath = $dataFile.physical_name
            ObjectID     = $objectId
            ObjectName   = $object.Name
            ObjectSchema = $object.SchemaName
            ObjectType   = $object.type_desc
        }
    }
    if ($resourceType -eq 'KEY') {
        $null = $WaitResource -match '^(?<Type>[A-Z]*): (?<dbid>[0-9]*):(?<frodo>[0-9]*) (?<physloc>\(.*\))$'
        $indexSql = "SELECT
                        sp.object_id AS ObjectID,
                        OBJECT_SCHEMA_NAME(sp.object_id) AS SchemaName,
                        sao.name AS ObjectName,
                        si.name AS IndexName
                    FROM
                        sys.partitions sp INNER JOIN sys.indexes si ON sp.index_id=si.index_id AND sp.object_id=si.object_id
                            INNER JOIN sys.all_objects sao ON sp.object_id=sao.object_id
                    WHERE
                        hobt_id = $($matches.frodo);
            "
        $index = $server.databases[$dbName].Query($indexSql)
        if ($null -eq $index) {
            Write-Message -Level Warning -Message "Heap or B-Tree with ID $($matches.frodo) can not be found in $dbName on $server"
            return
        }
        $output = [PSCustomObject]@{
            DatabaseID   = $dbId
            DatabaseName = $dbName
            SchemaName   = $index.SchemaName
            IndexName    = $index.IndexName
            ObjectID     = $index.ObjectID
            Objectname   = $index.ObjectName
            HobtID       = $matches.frodo
        }
        if ($row -eq $True) {
            $dataSql = "SELECT * FROM $($index.SchemaName).$($index.ObjectName) WITH (NOLOCK) WHERE %%lockres%% ='$($matches.physloc)'"
            $data = $server.databases[$dbName].query($dataSql)
            if ($null -eq $data) {
                Write-Message -Level warning -Message "Could not retrieve the data. It may have been deleted or moved since the wait resource value was generated"
            } else {
                $output | Add-Member -Type NoteProperty -Name ObjectData -Value $data
                $output | Select-Object * -ExpandProperty ObjectData
            }
        } else {
            $output
        }
    }
} $server $WaitResource $Row $EnableException $__boundVerbose $__boundDebug 3>&1
""";
}
