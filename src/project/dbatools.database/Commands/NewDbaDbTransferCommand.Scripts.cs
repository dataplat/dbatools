#nullable enable

namespace Dataplat.Dbatools.Commands;

// Hop script constants (the verbatim retired PS bodies) - split out per the repo 400-line file limit.
public sealed partial class NewDbaDbTransferCommand
{

    // PS: the begin block VERBATIM. Its single statement creates the ArrayList that process fills
    // and end consumes; the sentinel carries that INSTANCE out so .Add() accumulates on the shared
    // reference across every later hop.
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

    . {
        $objectCollection = New-Object System.Collections.ArrayList
    }

    $__oc = Get-Variable -Name objectCollection -Scope 0 -ErrorAction Ignore
    # PLAIN ASSIGNMENT, never "$( if (...) { $__oc.Value } )". A $() subexpression sends its result
    # through the pipeline, which ENUMERATES collections: an EMPTY ArrayList becomes $null and a
    # populated one collapses to its single element (measured: an ArrayList of one string came back
    # typed String). Either way the carried collection is destroyed and .Add() accumulates nothing.
    $__ocv = $null
    if ($__oc) { $__ocv = $__oc.Value }
    # ObjectCollectionAssigned: begin creates the ArrayList unconditionally (source :152), so this
    # is always $true here - carried for fleet-idiom consistency and defense (a future conditional
    # begin would then be safe), and it makes the seed a no-op when unset rather than a null local.
    @{ __newDbaDbTransferBegin = @{ ObjectCollection = $__ocv; ObjectCollectionAssigned = [bool]$__oc } }
} $EnableException $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";
    // PS: the process block VERBATIM, dot-sourced so its three early returns exit only the body.
    // Edits: two Test-Bound probes become carried boundness flags, plus -FunctionName stamps.
    // $objectCollection is restored from the carry BEFORE the body so .Add() lands on the same
    // ArrayList begin created, then handed back for the next record and ultimately for end.
    private const string ProcessScript = """
param($SqlInstance, $Database, $InputObject, $EnableException, $__state, $__boundSqlInstance, $__boundDatabase, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter]$SqlInstance, [string]$Database, [Microsoft.SqlServer.Management.Smo.NamedSmoObject[]]$InputObject, $EnableException, $__state, $__boundSqlInstance, $__boundDatabase, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

    # begin's ArrayList - the same instance, so .Add() accumulates across records
    if ($null -ne $__state.ObjectCollectionAssigned -and [bool]$__state.ObjectCollectionAssigned) { $objectCollection = $__state.ObjectCollection }

    . {
        if (-not $__boundSqlInstance) {
            Stop-Function -Message "Source instance was not specified" -FunctionName New-DbaDbTransfer
            return
        }
        if (-not $__boundDatabase) {
            Stop-Function -Message "Source database was not specified" -FunctionName New-DbaDbTransfer
            return
        }
        foreach ($object in $InputObject) {
            if (-not $object) {
                Stop-Function -Message "Object is empty" -FunctionName New-DbaDbTransfer
                return
            }
            $objectCollection.Add($object) | Out-Null
        }

    }

    $__oc = Get-Variable -Name objectCollection -Scope 0 -ErrorAction Ignore
    # plain assignment - see the note in BeginScript; $() would enumerate the ArrayList away
    $__ocv = $null
    if ($__oc) { $__ocv = $__oc.Value }
    @{ __newDbaDbTransferProcess = @{ ObjectCollection = $__ocv; ObjectCollectionAssigned = [bool]$__oc } }
} $SqlInstance $Database $InputObject $EnableException $__state $__boundSqlInstance $__boundDatabase $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";
    // PS: the end block VERBATIM, dot-sourced so its early returns exit only the body. Edits: three
    // Test-Bound probes become carried boundness flags, plus -FunctionName stamps.
    //
    // $DestinationDatabase is the DEF-007 bind-time default "= $Database" (:133). It is resolved here
    // rather than by a C# initializer, and $__boundDestinationDatabase still reports what the CALLER
    // passed so the "Initial Catalog" fallback at :225 keeps firing.
    private const string EndScript = """
param($SqlInstance, $SqlCredential, $DestinationSqlInstance, $DestinationSqlCredential, $Database, $DestinationDatabase, $BatchSize, $BulkCopyTimeOut, $ScriptingOption, $CopyAllObjects, $CopyAll, $SchemaOnly, $DataOnly, $EnableException, $__state, $__boundDestinationDatabase, $__boundSchemaOnly, $__boundDataOnly, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter]$SqlInstance, [PSCredential]$SqlCredential, [Dataplat.Dbatools.Parameter.DbaInstanceParameter]$DestinationSqlInstance, [PSCredential]$DestinationSqlCredential, [string]$Database, [string]$DestinationDatabase, [int]$BatchSize, [int]$BulkCopyTimeOut, [Microsoft.SqlServer.Management.Smo.ScriptingOptions]$ScriptingOption, $CopyAllObjects, [string[]]$CopyAll, $SchemaOnly, $DataOnly, $EnableException, $__state, $__boundDestinationDatabase, $__boundSchemaOnly, $__boundDataOnly, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

    # DEF-007: the source's "[string]$DestinationDatabase = $Database" bind-time default
    if (-not $__boundDestinationDatabase) { $DestinationDatabase = $Database }
    # the accumulator begin created and every process record filled
    if ($null -ne $__state.ObjectCollectionAssigned -and [bool]$__state.ObjectCollectionAssigned) { $objectCollection = $__state.ObjectCollection }

    . {
        try {
            $sourceDb = Get-DbaDatabase -SqlInstance $SqlInstance -SqlCredential $SqlCredential -Database $Database -EnableException
        } catch {
            Stop-Function -Message "Failed to retrieve database from the source instance $SqlInstance" -ErrorRecord $_ -FunctionName New-DbaDbTransfer
            return
        }
        if (-not $sourceDb) {
            Stop-Function -Message "Database $Database not found on $SqlInstance" -FunctionName New-DbaDbTransfer
            return
        } elseif ($sourceDb.Count -gt 1) {
            Stop-Function -Message "More than one database found on $SqlInstanced with the parameters provided" -FunctionName New-DbaDbTransfer
            return
        }
        # Create transfer object and define properties based on parameters
        $transfer = New-Object Microsoft.SqlServer.Management.Smo.Transfer($sourceDb)
        foreach ($object in $objectCollection) {
            $transfer.ObjectList.Add($object) | Out-Null
        }
        $transfer.BatchSize = $BatchSize
        $transfer.BulkCopyTimeOut = $BulkCopyTimeOut
        $transfer.CopyAllObjects = $CopyAllObjects
        foreach ($copyType in $CopyAll) {
            $transfer."CopyAll$copyType" = $true
        }
        if ($ScriptingOption) { $transfer.Options = $ScriptingOption }

        # Add destination connection parameters
        # Infer SSL/TLS settings from source connection
        $sourceTrustCert = $sourceDb.Parent.ConnectionContext.TrustServerCertificate
        $sourceEncrypt = $sourceDb.Parent.ConnectionContext.EncryptConnection

        if ($DestinationSqlInstance.IsConnectionString) {
            $connString = $DestinationSqlInstance.InputObject
        } elseif ($DestinationSqlInstance.Type -eq 'RegisteredServer' -and $DestinationSqlInstance.InputObject.ConnectionString) {
            $connString = $DestinationSqlInstance.InputObject.ConnectionString
        } elseif ($DestinationSqlInstance.Type -eq 'Server' -and $DestinationSqlInstance.InputObject.ConnectionContext.ConnectionString) {
            $connString = $DestinationSqlInstance.InputObject.ConnectionContext.ConnectionString
        } else {
            $transfer.DestinationServer = $DestinationSqlInstance.InputObject
            $transfer.DestinationLoginSecure = $true
        }

        # Build connection string for destination with SSL settings from source
        $destServer = $null
        $destDatabase = $DestinationDatabase
        $destIntegratedSecurity = $true
        $destUserName = $null
        $destPassword = $null

        if ($connString) {
            $connStringBuilder = New-Object Microsoft.Data.SqlClient.SqlConnectionStringBuilder $connString
            $destServer = if ($srv = $connStringBuilder["Data Source"]) { $srv } else { "localhost" }
            if (($db = $connStringBuilder["Initial Catalog"]) -and (-not $__boundDestinationDatabase)) {
                $destDatabase = $db
            }
            $destIntegratedSecurity = $connStringBuilder["Integrated Security"]
            $destUserName = $connStringBuilder["User ID"]
            $destPassword = $connStringBuilder["Password"]
        } else {
            $destServer = $DestinationSqlInstance.InputObject
        }

        # Override with DestinationSqlCredential if provided
        if ($DestinationSqlCredential) {
            $destIntegratedSecurity = $false
            $destUserName = $DestinationSqlCredential.UserName
            $destPassword = $DestinationSqlCredential.GetNetworkCredential().Password
        }

        # Build connection string with SSL settings from source
        $destConnStringBuilder = New-Object Microsoft.Data.SqlClient.SqlConnectionStringBuilder
        $destConnStringBuilder["Data Source"] = $destServer
        $destConnStringBuilder["Initial Catalog"] = $destDatabase
        $destConnStringBuilder["Integrated Security"] = $destIntegratedSecurity
        $destConnStringBuilder["TrustServerCertificate"] = $sourceTrustCert
        $destConnStringBuilder["Encrypt"] = $sourceEncrypt

        if (-not $destIntegratedSecurity) {
            $destConnStringBuilder["User ID"] = $destUserName
            $destConnStringBuilder["Password"] = $destPassword
        }

        # Create ServerConnection with SSL settings
        $destSqlConnection = New-Object Microsoft.Data.SqlClient.SqlConnection $destConnStringBuilder.ConnectionString
        $destServerConnection = New-Object Microsoft.SqlServer.Management.Common.ServerConnection $destSqlConnection
        $transfer.DestinationServerConnection = $destServerConnection

        # Also set individual properties for backward compatibility
        $transfer.DestinationServer = $destServer
        $transfer.DestinationDatabase = $destDatabase
        $transfer.DestinationLoginSecure = $destIntegratedSecurity
        if (-not $destIntegratedSecurity) {
            $transfer.DestinationLogin = $destUserName
            $transfer.DestinationPassword = $destPassword
        }
        if ($__boundSchemaOnly) { $transfer.CopyData = -not $SchemaOnly }
        if ($__boundDataOnly) { $transfer.CopySchema = -not $DataOnly }

        return $transfer
    }
} $SqlInstance $SqlCredential $DestinationSqlInstance $DestinationSqlCredential $Database $DestinationDatabase $BatchSize $BulkCopyTimeOut $ScriptingOption $CopyAllObjects $CopyAll $SchemaOnly $DataOnly $EnableException $__state $__boundDestinationDatabase $__boundSchemaOnly $__boundDataOnly $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";
}
