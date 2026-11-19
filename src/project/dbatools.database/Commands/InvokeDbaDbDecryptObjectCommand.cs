#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Decrypts encrypted stored procedures, functions, views, and triggers via a dedicated admin
/// connection. Port of public/Invoke-DbaDbDecryptObject.ps1; the workflow remains a module-scoped
/// PowerShell compatibility hop.
///
/// SqlInstance is a SCALAR ValueFromPipeline parameter, so process fires once per piped instance.
/// The command ships as THREE hops (begin, process, end), but the source's begin block is not a
/// single verbatim hop because its pieces have different lifetimes:
///
///  - The XOR decrypt helper (function Invoke-DecryptData) and the $encoding setup are pure setup
///    consumed only inside process; they are recreated at the top of the process hop each record
///    (deterministic from $EncodingType, so per-record equals the function's run-once begin).
///  - The $objectCollection ArrayList is an ACCUMULATOR: the source creates it once in begin,
///    appends each record's encrypted objects, and NEVER clears it, so the "foreach ($object in
///    $objectCollection)" loop reprocesses the whole accumulated set on every record (a source
///    quirk - later records re-decrypt earlier records' objects against the current record's
///    server). It rides a state sentinel across records so that behavior is preserved bug-for-bug.
///  - Only the export-directory creation stays in a genuine BEGIN hop, so it runs ONCE (its
///    Test-Path guard makes re-running idempotent, but a failure would warn per-record if it ran
///    in process), and because its "Stop-Function -Target $instance" binds $instance while
///    $instance is UNBOUND in begin - a source quirk that would change if the block ran inside the
///    process foreach where $instance is the loop variable.
///
/// INTERRUPT CARRY (vestigial here, preserved verbatim). Stop-Function sets the module interrupt
/// flag ONLY on its non-Continue path; a "Stop-Function -Continue" warns and calls continue without
/// ever setting it. EVERY Stop-Function in this command - the one begin export-dir failure and all
/// eight process failures - is -Continue, so the interrupt flag is never raised and the source's
/// process-top "if (Test-FunctionInterrupt) { return }" never fires. The port keeps that check
/// verbatim and threads the flag through each hop's Get-Variable -Scope 0 sentinel anyway, so the
/// machinery stays byte-faithful to the source; it simply never triggers for this command. A begin
/// export-dir failure therefore does NOT suppress process (matching the source), and EndProcessing
/// is intentionally not gated on the carried flag.
///
/// The source reads $Force (undeclared) at the export New-Item -Force:$Force - it rides verbatim as
/// an unset read ($false). No ShouldProcess (the source declares none), no Test-Bound, no
/// Get-PSCallStack. In-hop Stop-Function/Write-Message carry -FunctionName; the nested
/// Get-DbaSpConfigure/Connect-DbaInstance/Disconnect-DbaInstance resolve through the module scope.
/// Surface pinned by migration/baselines/Invoke-DbaDbDecryptObject.json (positions 0-5, no sets).
/// </summary>
[Cmdlet(VerbsLifecycle.Invoke, "DbaDbDecryptObject")]
public sealed class InvokeDbaDbDecryptObjectCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance.</summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 0)]
    public DbaInstanceParameter SqlInstance { get; set; } = null!;

    /// <summary>Alternative credential for the target instance.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>The database(s) containing the encrypted objects.</summary>
    [Parameter(Mandatory = true, Position = 2)]
    public object[]? Database { get; set; }

    /// <summary>Only decrypt these named objects; omit to decrypt every encrypted object.</summary>
    [Parameter(Position = 3)]
    [PsStringArrayCast]
    public string[]? ObjectName { get; set; }

    /// <summary>Text encoding used to interpret the decrypted bytes.</summary>
    [Parameter(Position = 4)]
    [ValidateSet("ASCII", "UTF8")]
    [PsStringCast]
    public string EncodingType { get; set; } = "ASCII";

    /// <summary>Directory to write the decrypted object scripts to; created if absent.</summary>
    [Parameter(Position = 5)]
    [PsStringCast]
    public string? ExportDestination { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    // Carries the source's function-scope interrupt flag between hops. Vestigial for this command
    // (every Stop-Function is -Continue, which never sets it) but preserved verbatim; see the class doc.
    private bool _interrupted;
    // Carries the $objectCollection accumulator (an ArrayList held opaquely - never cast in C#).
    private Hashtable? _state;

    protected override void BeginProcessing()
    {
        if (Interrupted)
            return;

        NestedCommand.InvokeScopedStreaming(this, item =>
        {
            if (item?.BaseObject is Hashtable sentinel && sentinel.ContainsKey("__invokeDbaDbDecryptObjectBegin"))
            {
                if (sentinel["__invokeDbaDbDecryptObjectBegin"] is Hashtable state)
                    _interrupted = LanguagePrimitives.IsTrue(state["Interrupted"]);
                return;
            }
            if (item?.BaseObject is ErrorRecord nestedError)
            {
                NestedCommand.RemoveDuplicateError(this, nestedError);
                WriteError(NestedCommand.PreserveErrorIdentity(nestedError));
                return;
            }
            WriteObject(item);
        }, BeginScript,
            ExportDestination, EnableException.ToBool(),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    protected override void ProcessRecord()
    {
        if (Interrupted || _interrupted)
            return;

        NestedCommand.InvokeScopedStreaming(this, item =>
        {
            if (item?.BaseObject is Hashtable sentinel && sentinel.ContainsKey("__invokeDbaDbDecryptObjectProcess"))
            {
                if (sentinel["__invokeDbaDbDecryptObjectProcess"] is Hashtable result)
                {
                    _state = result["State"] as Hashtable;
                    _interrupted = LanguagePrimitives.IsTrue(result["Interrupted"]);
                }
                return;
            }
            if (item?.BaseObject is ErrorRecord nestedError)
            {
                NestedCommand.RemoveDuplicateError(this, nestedError);
                WriteError(NestedCommand.PreserveErrorIdentity(nestedError));
                return;
            }
            WriteObject(item);
        }, ProcessScript,
            SqlInstance, SqlCredential, Database, ObjectName, EncodingType, ExportDestination,
            EnableException.ToBool(), _state,
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    protected override void EndProcessing()
    {
        if (Interrupted)
            return;

        NestedCommand.InvokeScopedStreaming(this, item =>
        {
            if (item?.BaseObject is ErrorRecord nestedError)
            {
                NestedCommand.RemoveDuplicateError(this, nestedError);
                WriteError(NestedCommand.PreserveErrorIdentity(nestedError));
                return;
            }
            WriteObject(item);
        }, EndScript,
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    // PS: the begin block's export-directory side effect VERBATIM, dot-sourced. $instance is
    // unbound here exactly as in the source begin (its Stop-Function -Target binds $null). The
    // helper/encoding/ArrayList setup is NOT here - those are process-hop preamble (see the class
    // doc). Edit: -FunctionName on the one Stop-Function (which is -Continue, so it never sets the
    // interrupt). The sentinel reports the interrupt flag verbatim - always false for this command.
    private const string BeginScript = """
param($ExportDestination, $EnableException, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    param([string]$ExportDestination, $EnableException, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

    . {
        # Check the export parameter
        if ($ExportDestination -and -not (Test-Path $ExportDestination)) {
            try {
                # Create the new destination
                New-Item -Path $ExportDestination -ItemType Directory -Force | Out-Null
            } catch {
                Stop-Function -Message "Couldn't create destination folder $ExportDestination" -ErrorRecord $_ -Target $instance -Continue -FunctionName Invoke-DbaDbDecryptObject
            }
        }
    }

    $__iv = Get-Variable -Name __dbatools_interrupt_function_78Q9VPrM6999g6zo24Qn83m09XF56InEn4hFrA8Fwhu5xJrs6r -Scope 0 -ErrorAction Ignore
    @{ __invokeDbaDbDecryptObjectBegin = @{ Interrupted = [bool]($__iv -and $__iv.Value) } }
} $ExportDestination $EnableException $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";
    // PS: the process block VERBATIM per record, dot-sourced. The begin-scoped decrypt helper and
    // $encoding are recreated here (pure setup); the $objectCollection accumulator is restored from
    // the carried state (or created on the first record) so the source's grow-and-reprocess-whole
    // behavior survives across records. Edits: -FunctionName on the ten direct Stop-Function/
    // Write-Message calls (all -Continue, so none sets the interrupt). The sentinel carries the
    // accumulator and the interrupt flag verbatim (the flag stays false for this command).
    private const string ProcessScript = """
param($SqlInstance, $SqlCredential, $Database, $ObjectName, $EncodingType, $ExportDestination, $EnableException, $__state, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter]$SqlInstance, [PSCredential]$SqlCredential, [object[]]$Database, [string[]]$ObjectName, [string]$EncodingType, [string]$ExportDestination, $EnableException, $__state, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

    # begin-scoped decrypt helper, recreated (pure - the source defines it in begin)
            function Invoke-DecryptData() {
                param(
                    [parameter(Mandatory)]
                    [byte[]]$Secret,
                    [parameter(Mandatory)]
                    [byte[]]$KnownPlain,
                    [parameter(Mandatory)]
                    [byte[]]$KnownSecret
                )
    
                # Declare pointers
                [int]$i = 0
    
                # Loop through each of the characters and apply an XOR to decrypt the data
                $result = $(
    
                    # Loop through the byte string
                    while ($i -lt $Secret.Length) {
    
                        # Compare the byte string character to the key character using XOR
                        if ($i -lt $Secret.Length) {
                            $Secret[$i] -bxor $KnownPlain[$i] -bxor $KnownSecret[$i]
                        }
    
                        # Increment the byte string indicator
                        $i += 2
    
                    } # end while loop
    
                ) # end data value
    
                # Get the string value from the data
                $decryptedData = $Encoding.GetString($result)
    
                # Return the decrypted data
                return $decryptedData
            }

    # begin-scoped encoding setup, recreated (deterministic from $EncodingType)
            # Set the encoding
            if ($EncodingType -eq 'ASCII') {
                $encoding = [System.Text.Encoding]::ASCII
            } elseif ($EncodingType -eq 'UTF8') {
                $encoding = [System.Text.Encoding]::UTF8
            }

    # the source's begin-scoped $objectCollection ACCUMULATOR: restore the carried instance, or
    # create it on the first record. It is never cleared, so it grows and is reprocessed whole each
    # record (a source quirk preserved).
    if ($null -ne $__state -and $__state.ContainsKey("ObjectCollection")) {
        $objectCollection = $__state.ObjectCollection
    } else {
        $objectCollection = New-Object System.Collections.ArrayList
    }

    . {

        if (Test-FunctionInterrupt) { return }

        # Loop through all the instances
        foreach ($instance in $SqlInstance) {

            # Check the configuration of the intance to see if the DAC is enabled
            $config = Get-DbaSpConfigure -SqlInstance $instance -SqlCredential $SqlCredential -ConfigName RemoteDacConnectionsEnabled
            if ($config.ConfiguredValue -ne 1) {
                Stop-Function -Message "DAC is not enabled for instance $instance.`nPlease use 'Set-DbaSpConfigure -SqlInstance $instance -SqlCredential <credential> -ConfigName RemoteDacConnectionsEnabled -Value 1' to configure the instance to allow DAC connections" -Target $instance -Continue -FunctionName Invoke-DbaDbDecryptObject
            }

            # Try to connect to instance
            try {
                # Do we have a dedicated admin connection already?
                $dacConnected = $instance.Type -eq "Server" -and $instance.InputObject.ConnectionContext.ServerInstance -match "^ADMIN:"
                $dacOpened = $false
                if ($dacConnected) {
                    Write-Message -Level Verbose -Message "Reusing dedicated admin connection." -FunctionName Invoke-DbaDbDecryptObject -ModuleName "dbatools"
                    $server = $instance.InputObject
                } else {
                    Write-Message -Level Verbose -Message "Opening dedicated admin connection." -FunctionName Invoke-DbaDbDecryptObject -ModuleName "dbatools"
                    $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential -DedicatedAdminConnection -WarningAction SilentlyContinue
                    $dacOpened = $true
                }
            } catch {
                Stop-Function -Message "Error occurred while establishing connection to $instance" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue -FunctionName Invoke-DbaDbDecryptObject
            }

            # Get all the databases that compare to the database parameter
            $databaseCollection = $server.Databases | Where-Object { $_.Name -in $Database }

            # Use the table's schema for the trigger's schema. The schema name is not returned as a property for triggers (except in the URN).
            $triggerSchema = @{label = "Schema"; expression = { $_.Parent.Schema } }

            # Loop through each of databases
            foreach ($db in $databaseCollection) {

                $triggers = @($db.Tables | Where-Object { $_.IsSystemObject -eq $false } | ForEach-Object { $_.Triggers })

                # Get the objects
                if ($ObjectName) {
                    $storedProcedures = @($db.StoredProcedures | Where-Object { $_.Name -in $ObjectName -and $_.IsEncrypted -eq $true } | Select-Object Name, Schema, @{N = "ObjectType"; E = { 'StoredProcedure' } }, @{N = "SubType"; E = { '' } })
                    $functions = @($db.UserDefinedFunctions | Where-Object { $_.Name -in $ObjectName -and $_.IsEncrypted -eq $true } | Select-Object Name, Schema, @{N = "ObjectType"; E = { "UserDefinedFunction" } }, @{N = "SubType"; E = { $_.FunctionType.ToString().Trim() } })
                    $views = @($db.Views | Where-Object { $_.Name -in $ObjectName -and $_.IsEncrypted -eq $true } | Select-Object Name, Schema, @{N = "ObjectType"; E = { 'View' } }, @{N = "SubType"; E = { '' } })
                    $triggers = @($triggers | Where-Object { $_.Name -in $ObjectName -and $_.IsEncrypted -eq $true } | Select-Object Name, $triggerSchema, Parent, @{N = "ObjectType"; E = { 'Trigger' } }, @{N = "SubType"; E = { '' } })
                } else {
                    # Get all encrypted objects
                    $storedProcedures = @($db.StoredProcedures | Where-Object { $_.IsEncrypted -eq $true } | Select-Object Name, Schema, @{N = "ObjectType"; E = { 'StoredProcedure' } }, @{N = "SubType"; E = { '' } })
                    $functions = @($db.UserDefinedFunctions | Where-Object { $_.IsEncrypted -eq $true } | Select-Object Name, Schema, @{N = "ObjectType"; E = { "UserDefinedFunction" } }, @{N = "SubType"; E = { $_.FunctionType.ToString().Trim() } })
                    $views = @($db.Views | Where-Object { $_.IsEncrypted -eq $true } | Select-Object Name, Schema, @{N = "ObjectType"; E = { 'View' } }, @{N = "SubType"; E = { '' } })
                    $triggers = @($triggers | Where-Object { $_.IsEncrypted -eq $true } | Select-Object Name, $triggerSchema, Parent, @{N = "ObjectType"; E = { 'Trigger' } }, @{N = "SubType"; E = { '' } })
                }

                # Check if there are any objects
                if ($storedProcedures.Count -ge 1) {
                    $objectCollection += $storedProcedures
                }
                if ($functions.Count -ge 1) {
                    $objectCollection += $functions
                }
                if ($views.Count -ge 1) {
                    $objectCollection += $views
                }
                if ($triggers.Count -ge 1) {
                    $objectCollection += $triggers
                }
                # Loop through all the objects
                foreach ($object in $objectCollection) {

                    # Setup the query to get the secret. Include the schema name to find the object. Exclude null values in sys.sysobjvalues for triggers.
                    $querySecret = "SELECT imageval AS Value FROM sys.sysobjvalues WHERE objid = OBJECT_ID('$($object.Schema).$($object.Name)') AND imageval IS NOT NULL"

                    # Get the result of the secret query
                    try {
                        $secret = $server.Databases[$db.Name].Query($querySecret)
                    } catch {
                        Stop-Function -Message "Couldn't retrieve secret from $instance" -ErrorRecord $_ -Target $instance -Continue -FunctionName Invoke-DbaDbDecryptObject
                    }

                    # Check if at least a value came back
                    if ($secret) {

                        # Setup a known plain command and get the binary version of it
                        switch ($object.ObjectType) {

                            'StoredProcedure' {
                                $queryKnownPlain = (" " * $secret.Value.Length) + "ALTER PROCEDURE [$($object.Schema)].[$($object.Name)] WITH ENCRYPTION AS RETURN 0;"
                            }
                            'UserDefinedFunction' {

                                switch ($object.SubType) {
                                    'Inline' {
                                        $queryKnownPlain = (" " * $secret.value.length) + "ALTER FUNCTION [$($object.Schema)].[$($object.Name)]() RETURNS TABLE WITH ENCRYPTION AS RETURN SELECT 0 i;"
                                    }
                                    'Scalar' {
                                        $queryKnownPlain = (" " * $secret.value.length) + "ALTER FUNCTION [$($object.Schema)].[$($object.Name)]() RETURNS INT WITH ENCRYPTION AS BEGIN RETURN 0 END;"
                                    }
                                    'Table' {
                                        $queryKnownPlain = (" " * $secret.value.length) + "ALTER FUNCTION [$($object.Schema)].[$($object.Name)]() RETURNS @r TABLE(i INT) WITH ENCRYPTION AS BEGIN RETURN END;"
                                    }
                                }
                            }
                            'View' {
                                $queryKnownPlain = (" " * $secret.Value.Length) + "ALTER VIEW [$($object.Schema)].[$($object.Name)] WITH ENCRYPTION AS SELECT NULL AS [Value];"
                            }
                            'Trigger' {
                                $queryKnownPlain = (" " * $secret.Value.Length) + "ALTER TRIGGER [$($object.Schema)].[$($object.Name)] ON $($object.Parent) WITH ENCRYPTION AFTER INSERT AS RAISERROR (''Invoke-DbaDbDecryptObject'', 16, 10);"
                            }
                        }

                        # Convert the known plain into binary
                        if ($queryKnownPlain) {
                            try {
                                $knownPlain = $encoding.GetBytes(($queryKnownPlain))
                            } catch {
                                Stop-Function -Message "Couldn't convert the known plain to binary" -ErrorRecord $_ -Target $instance -Continue -FunctionName Invoke-DbaDbDecryptObject
                            }
                        } else {
                            Stop-Function -Message "Something went wrong setting up the known plain" -Target $instance -Continue -FunctionName Invoke-DbaDbDecryptObject
                        }

                        # Setup the query to change the object in SQL Server and roll it back getting the encrypted version
                        # Exclude null values in sys.sysobjvalues for triggers and include the full schema and object name.
                        $queryKnownSecret = "
                            BEGIN TRANSACTION;
                                EXEC ('$queryKnownPlain');
                                SELECT imageval AS Value
                                FROM sys.sysobjvalues
                                WHERE objid = OBJECT_ID('$($object.Schema).$($object.Name)')
                                AND imageval IS NOT NULL;
                            ROLLBACK;
                        "

                        # Get the result for the known encrypted
                        try {
                            $knownSecret = $server.Databases[$db.Name].Query($queryKnownSecret)
                        } catch {
                            Stop-Function -Message "Couldn't retrieve known secret from $instance" -ErrorRecord $_ -Target $instance -Continue -FunctionName Invoke-DbaDbDecryptObject
                        }

                        # Get the result
                        $result = Invoke-DecryptData -Secret $secret.value -KnownPlain $knownPlain -KnownSecret $knownSecret.value

                        # Check if the results need to be exported
                        $filePath = $null
                        if ($ExportDestination) {
                            # make up the file name
                            $filename = "$($object.Schema).$($object.Name).sql"

                            # Check the export destination
                            if ($ExportDestination.EndsWith("\")) {
                                $destinationFolder = "$ExportDestination$instance\$($db.Name)\$($object.ObjectType)\"
                            } else {
                                $destinationFolder = "$ExportDestination\$instance\$($db.Name)\$($object.ObjectType)\"
                            }

                            # Check if the destination folder exists
                            if (-not (Test-Path $destinationFolder)) {
                                try {
                                    # Create the new destination
                                    New-Item -Path $destinationFolder -ItemType Directory -Force:$Force | Out-Null
                                } catch {
                                    Stop-Function -Message "Couldn't create destination folder $destinationFolder" -ErrorRecord $_ -Target $instance -Continue -FunctionName Invoke-DbaDbDecryptObject
                                }
                            }

                            # Combine the destination folder and the file name to get the path
                            $filePath = $destinationFolder + $filename

                            # Export the result
                            try {
                                $result | Out-File -FilePath $filePath -Force
                            } catch {
                                Stop-Function -Message "Couldn't export the results of $($object.Name) to $filePath" -ErrorRecord $_ -Target $instance -Continue -FunctionName Invoke-DbaDbDecryptObject
                            }

                        }

                        # Add the results to the custom object
                        [PSCustomObject]@{
                            ComputerName = $instance.ComputerName
                            InstanceName = $server.ServiceName
                            SqlInstance  = $server.DomainInstanceName
                            Database     = $db.Name
                            Type         = $object.ObjectType
                            Schema       = $object.Schema
                            Name         = $object.Name
                            FullName     = "$($object.Schema).$($object.Name)"
                            Script       = $result
                            OutputFile   = $filePath
                        }
                    }
                }
            }
            if ($dacOpened) {
                $null = $server | Disconnect-DbaInstance -WhatIf:$false
            }
        }
    }

    $__iv = Get-Variable -Name __dbatools_interrupt_function_78Q9VPrM6999g6zo24Qn83m09XF56InEn4hFrA8Fwhu5xJrs6r -Scope 0 -ErrorAction Ignore
    @{ __invokeDbaDbDecryptObjectProcess = @{ Interrupted = [bool]($__iv -and $__iv.Value); State = @{ ObjectCollection = $objectCollection } } }
} $SqlInstance $SqlCredential $Database $ObjectName $EncodingType $ExportDestination $EnableException $__state $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";
    // PS: the end block VERBATIM. Edit: -FunctionName on the one Write-Message.
    private const string EndScript = """
param($__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    param($__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }
            Write-Message -Message "Finished decrypting data" -Level Verbose -FunctionName Invoke-DbaDbDecryptObject -ModuleName "dbatools"
} $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";
}
