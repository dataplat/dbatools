#nullable enable

using System;
using System.Collections;
using System.Collections.ObjectModel;
using System.Management.Automation;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Validates NTFS allocation units and identifies SQL-hosting volumes. Port of
/// public/Test-DbaDiskAllocation.ps1 (W1-128). BeginProcessing creates the source DCOM
/// CimSessionOption once. The full process body rides one module-scoped PowerShell hop so
/// object-array input coercion, WSMan/DCOM fallback, private service/connection helpers,
/// Stop-Function flow, CIM/ETS member reads, aliases, and Select-DefaultView retain engine
/// semantics. Surface pinned by migration/baselines/Test-DbaDiskAllocation.json.
/// </summary>
[Cmdlet(VerbsDiagnostic.Test, "DbaDiskAllocation")]
[OutputType(typeof(ArrayList), typeof(bool))]
public sealed class TestDbaDiskAllocationCommand : DbaBaseCmdlet
{
    /// <summary>The target computers (source accepts arbitrary objects).</summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 0)]
    public object[] ComputerName { get; set; } = null!;

    /// <summary>Skip SQL service/file detection.</summary>
    [Parameter]
    public SwitchParameter NoSqlCheck { get; set; }

    /// <summary>Alternative SQL credential.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>Alternative Windows credential for CIM access.</summary>
    [Parameter(Position = 2)]
    public PSCredential? Credential { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    private object? _sessionOptions;

    protected override void BeginProcessing()
    {
        Collection<PSObject> values = NestedCommand.InvokeScoped(this, BeginScript);
        if (values.Count == 1)
            _sessionOptions = values[0]?.BaseObject;
        else if (values.Count > 1)
            _sessionOptions = values;
    }

    protected override void ProcessRecord()
    {
        NestedCommand.InvokeScopedStreaming(this, item =>
        {
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
            ComputerName, NoSqlCheck.ToBool(), SqlCredential, Credential,
            EnableException.ToBool(), _sessionOptions, NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    private const string BeginScript = """
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    New-CimSessionOption -Protocol DCOM
}
""";

    private const string ProcessScript = """
param($ComputerName, $NoSqlCheck, $SqlCredential, $Credential, $EnableException, $sessionoptions, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    param($ComputerName, $NoSqlCheck, $SqlCredential, $Credential, $EnableException, $sessionoptions)

        foreach ($computer in $ComputerName) {
            $fullComputerName = Resolve-DbaComputerName -ComputerName $computer -Credential $Credential

            if (!$fullComputerName) {
                Stop-Function -Message "Couldn't resolve hostname $computer. Skipping." -Continue -FunctionName Test-DbaDiskAllocation
            }

            Write-Message -Level Verbose -Message "Creating CimSession on $fullComputerName over WSMan." -FunctionName Test-DbaDiskAllocation -ModuleName "dbatools"

            if (!$Credential) {
                $cimSession = New-CimSession -ComputerName $fullComputerName -ErrorAction SilentlyContinue
            } else {
                $cimSession = New-CimSession -ComputerName $fullComputerName -ErrorAction SilentlyContinue -Credential $Credential
            }

            if ($null -eq $cimSession.id) {
                Write-Message -Level Verbose -Message "Creating CimSession on $fullComputerName over WSMan failed. Creating CimSession on $fullComputerName over DCOM." -FunctionName Test-DbaDiskAllocation -ModuleName "dbatools"

                if (!$Credential) {
                    $cimSession = New-CimSession -ComputerName $fullComputerName -SessionOption $sessionoptions -ErrorAction SilentlyContinue
                } else {
                    $cimSession = New-CimSession -ComputerName $fullComputerName -SessionOption $sessionoptions -ErrorAction SilentlyContinue -Credential $Credential
                }
            }

            if ($null -eq $cimSession.id) {
                Stop-Function -Message "Can't create CimSession on $fullComputerName" -Target $computer -FunctionName Test-DbaDiskAllocation
            }

            Write-Message -Level Verbose -Message "Getting Disk Allocation from $computer" -FunctionName Test-DbaDiskAllocation -ModuleName "dbatools"

            try {
                Write-Message -Level Verbose -Message "Getting disk information from $computer." -FunctionName Test-DbaDiskAllocation -ModuleName "dbatools"
                $disks = Get-CimInstance -CimSession $cimSession -ClassName win32_volume -Filter "FileSystem='NTFS'" -ErrorAction Stop | Sort-Object -Property Name
            } catch {
                Stop-Function -Message "Can't connect to WMI on $computer." -FunctionName Test-DbaDiskAllocation
                return
            }

            if ($NoSqlCheck -eq $false) {
                Write-Message -Level Verbose -Message "Checking for SQL Services" -FunctionName Test-DbaDiskAllocation -ModuleName "dbatools"
                $sqlInstances = (Get-DbaService -ComputerName $fullComputerName -Type Engine -AdvancedProperties | Where-Object State -eq Running | Sort-Object -Property Name).SqlInstance
                Write-Message -Level Verbose -Message "$($sqlInstances.Count) instance(s) found." -FunctionName Test-DbaDiskAllocation -ModuleName "dbatools"
            }

            foreach ($disk in $disks) {
                if (!$disk.name.StartsWith("\\")) {
                    $diskname = $disk.Name

                    if ($NoSqlCheck -eq $false) {
                        $sqldisk = $false

                        foreach ($instance in $sqlInstances) {
                            try {
                                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
                            } catch {
                                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue -FunctionName Test-DbaDiskAllocation
                            }

                            $sql = "SELECT COUNT(*) AS Count FROM sys.master_files WHERE physical_name LIKE '$diskname%'"
                            $sqlcount = $server.Query($sql).Count
                            if ($sqlcount -gt 0) {
                                $sqldisk = $true
                                break
                            }
                        }
                    }

                    if ($disk.BlockSize -eq 65536) {
                        $IsBestPractice = $true
                    } else {
                        $IsBestPractice = $false
                    }

                    $windowsdrive = "$env:SystemDrive\"

                    if ($diskname -eq $windowsdrive) {
                        $IsBestPractice = $false
                    }

                    if ($NoSqlCheck -eq $false) {
                        $output = [PSCustomObject]@{
                            ComputerName   = $computer
                            DiskName       = $diskname
                            DiskLabel      = $disk.Label
                            BlockSize      = $disk.BlockSize
                            IsSqlDisk      = $sqldisk
                            IsBestPractice = $IsBestPractice
                        }
                        $defaults = 'ComputerName', 'DiskName', 'DiskLabel', 'BlockSize', 'IsSqlDisk', 'IsBestPractice'
                    } else {
                        $output = [PSCustomObject]@{
                            ComputerName   = $computer
                            DiskName       = $diskname
                            DiskLabel      = $disk.Label
                            BlockSize      = $disk.BlockSize
                            IsBestPractice = $IsBestPractice
                        }
                        $defaults = 'ComputerName', 'DiskName', 'DiskLabel', 'BlockSize', 'IsBestPractice'
                    }
                    # Add aliases for backwards compatibility
                    Add-Member -InputObject $output -MemberType AliasProperty -Name Server -Value ComputerName
                    Add-Member -InputObject $output -MemberType AliasProperty -Name Name -Value DiskName
                    Add-Member -InputObject $output -MemberType AliasProperty -Name Label -Value DiskLabel
                    Select-DefaultView -InputObject $output -Property $defaults
                }
            }
        }

} $ComputerName $NoSqlCheck $SqlCredential $Credential $EnableException $sessionoptions @__commonParameters 3>&1 2>&1
""";
}
