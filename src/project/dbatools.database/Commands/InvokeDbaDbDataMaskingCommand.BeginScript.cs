#nullable enable

namespace Dataplat.Dbatools.Commands;

// Hop begin-script constant - split per the repo 400-line file limit.
public sealed partial class InvokeDbaDbDataMaskingCommand
{

    // PS: the begin block VERBATIM, dot-sourced so its assignments land in the hop scope for
    // the sentinel. Edits: -FunctionName on the four Write-Message defaults. $Force rides as
    // the source's undeclared read. The sentinel carries the computed type lists and the
    // defaulted ints as one opaque state hashtable.
    private const string BeginScript = """
param($ModulusFactor, $CommandTimeout, $BatchSize, $Retry, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    param([int]$ModulusFactor, [int]$CommandTimeout, [int]$BatchSize, [int]$Retry, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

    . {
        if ($Force) { $ConfirmPreference = 'none' }

        $supportedDataTypes = @(
            'bit', 'bigint', 'bool',
            'char', 'date',
            'datetime', 'datetime2', 'decimal',
            'float',
            'int',
            'money',
            'nchar', 'ntext', 'nvarchar',
            'smalldatetime', 'smallint',
            'text', 'time', 'tinyint',
            'uniqueidentifier', 'userdefineddatatype',
            'varchar'
        )

        $supportedFakerMaskingTypes = Get-DbaRandomizedType | Select-Object Type -ExpandProperty Type -Unique

        $supportedFakerSubTypes = Get-DbaRandomizedType | Select-Object Subtype -ExpandProperty Subtype -Unique

        $supportedFakerSubTypes += "Date"

        # Set defaults
        if (-not $ModulusFactor) {
            $ModulusFactor = 10
            Write-Message -Level Verbose -Message "Modulus factor set to $ModulusFactor" -FunctionName Invoke-DbaDbDataMasking -ModuleName "dbatools"
        }

        if (-not $CommandTimeout) {
            $CommandTimeout = 300
            Write-Message -Level Verbose -Message "Command time-out set to $CommandTimeout" -FunctionName Invoke-DbaDbDataMasking -ModuleName "dbatools"
        }

        if (-not $BatchSize) {
            $BatchSize = 1000
            Write-Message -Level Verbose -Message "Batch size set to $BatchSize" -FunctionName Invoke-DbaDbDataMasking -ModuleName "dbatools"
        }

        if (-not $Retry) {
            $Retry = 1000
            Write-Message -Level Verbose -Message "Retry count set to $Retry" -FunctionName Invoke-DbaDbDataMasking -ModuleName "dbatools"
        }
    }

    @{ __invokeDbaDbDataMaskingBegin = @{ SupportedDataTypes = $supportedDataTypes; SupportedFakerMaskingTypes = $supportedFakerMaskingTypes; SupportedFakerSubTypes = $supportedFakerSubTypes; ModulusFactor = $ModulusFactor; CommandTimeout = $CommandTimeout; BatchSize = $BatchSize; Retry = $Retry; BeginForce = [bool]$Force } }
} $ModulusFactor $CommandTimeout $BatchSize $Retry $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";
}
