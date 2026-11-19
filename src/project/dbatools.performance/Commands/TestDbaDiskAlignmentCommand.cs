#nullable enable

using System;
using System.Collections;
using System.Collections.ObjectModel;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Tests Windows partition offsets against common stripe sizes. Port of
/// public/Test-DbaDiskAlignment.ps1 (W1-127). BeginProcessing creates the source DCOM
/// CimSessionOption once. The local Get-DiskAlignment helper and complete per-record body
/// ride one module-scoped PowerShell hop so CIM queries, SQL-disk filtering, dynamic
/// continues, DbaSize coercion, warning flow, and result shaping retain engine semantics.
/// The helper receives the outer command name explicitly because its source call-stack
/// default would otherwise observe the module-hop scriptblock rather than the retired
/// function. Surface pinned by migration/baselines/Test-DbaDiskAlignment.json.
/// </summary>
[Cmdlet(VerbsDiagnostic.Test, "DbaDiskAlignment")]
public sealed class TestDbaDiskAlignmentCommand : DbaBaseCmdlet
{
    /// <summary>The Windows computers whose partitions should be tested.</summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 0)]
    public DbaInstanceParameter[] ComputerName { get; set; } = null!;

    /// <summary>Alternative Windows credential for CIM access.</summary>
    [Parameter(Position = 1)]
    public PSCredential? Credential { get; set; }

    /// <summary>Alternative SQL credential (source quirk: the local helper does not bind it).</summary>
    [Parameter(Position = 2)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>Test all logical disks without restricting them to SQL files.</summary>
    [Parameter]
    public SwitchParameter NoSqlCheck { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    private object? _sessionOption;

    protected override void BeginProcessing()
    {
        Collection<PSObject> values = NestedCommand.InvokeScoped(this, BeginScript);
        if (values.Count == 1)
            _sessionOption = values[0]?.BaseObject;
        else if (values.Count > 1)
            _sessionOption = values;
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
            ComputerName, Credential, SqlCredential, NoSqlCheck.ToBool(),
            EnableException.ToBool(), _sessionOption, NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    private const string BeginScript = """
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    New-CimSessionOption -Protocol DCom
}
""";

    private const string ProcessScript = """
param($ComputerName, $Credential, $SqlCredential, $NoSqlCheck, $EnableException, $sessionoption, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    param($ComputerName, $Credential, $SqlCredential, $NoSqlCheck, $EnableException, $sessionoption)

        function Get-DiskAlignment {
            [CmdletBinding()]
            param (
                $cimSession,
                [string]$FunctionName = (Get-PSCallStack)[0].Command,
                [bool]$NoSqlCheck,
                [string]$ComputerName,
                [System.Management.Automation.PSCredential]$SqlCredential,
                [bool]$EnableException = $EnableException
            )

            $SqlInstances = @()
            $offsets = @()

            #region Retrieving partition/disk Information
            try {
                Write-Message -Level Verbose -Message "Gathering information about first partition on each disk for $ComputerName." -FunctionName $FunctionName -ModuleName "dbatools"

                try {
                    $partitions = Get-CimInstance -CimSession $cimSession -ClassName Win32_DiskPartition -Namespace "root\cimv2" -ErrorAction Stop
                } catch {
                    if ($_.Exception -match "namespace") {
                        Stop-Function -Message "Can't get disk alignment info for $ComputerName. Unsupported operating system." -InnerErrorRecord $_ -Target $ComputerName -FunctionName $FunctionName
                        return
                    } else {
                        Stop-Function -Message "Can't get disk alignment info for $ComputerName. Check logs for more details." -InnerErrorRecord $_ -Target $ComputerName -FunctionName $FunctionName
                        return
                    }
                }


                $disks = @()
                foreach ($partition in $partitions) {
                    $associators = Get-CimInstance -CimSession $cimSession -Query "ASSOCIATORS OF {Win32_DiskPartition.DeviceID=""$($partition.DeviceID.Replace("\", "\\"))""} WHERE AssocClass = Win32_LogicalDiskToPartition"
                    foreach ($assoc in $associators) {
                        $disks += [PSCustomObject]@{
                            BlockSize      = $partition.BlockSize
                            BootPartition  = $partition.BootPartition
                            Description    = $partition.Description
                            DiskIndex      = $partition.DiskIndex
                            Index          = $partition.Index
                            NumberOfBlocks = $partition.NumberOfBlocks
                            StartingOffset = $partition.StartingOffset
                            Type           = $partition.Type
                            Name           = $assoc.Name
                            Size           = $partition.Size
                        }
                    }
                }

                Write-Message -Level Verbose -Message "Gathered CIM information." -FunctionName $FunctionName -ModuleName "dbatools"
            } catch {
                Stop-Function -Message "Can't connect to CIM on $ComputerName." -FunctionName $FunctionName -InnerErrorRecord $_
                return
            }
            #endregion Retrieving partition Information

            #region Retrieving Instances
            if (-not $NoSqlCheck) {
                Write-Message -Level Verbose -Message "Checking for SQL Services." -FunctionName $FunctionName -ModuleName "dbatools"
                $sqlservices = Get-CimInstance -ClassName Win32_Service -CimSession $cimSession | Where-Object DisplayName -like 'SQL Server (*'
                foreach ($service in $sqlservices) {
                    $instance = $service.DisplayName.Replace('SQL Server (', '')
                    $instance = $instance.TrimEnd(')')

                    $instanceName = $instance.Replace("MSSQLSERVER", "Default")
                    Write-Message -Level Verbose -Message "Found instance $instanceName" -FunctionName $FunctionName -ModuleName "dbatools"
                    if ($instance -eq 'MSSQLSERVER') {
                        $SqlInstances += $ComputerName
                    } else {
                        $SqlInstances += "$ComputerName\$instance"
                    }
                }
                $sqlcount = $SqlInstances.Count
                Write-Message -Level Verbose -Message "$sqlcount instance(s) found." -FunctionName $FunctionName -ModuleName "dbatools"
            }
            #endregion Retrieving Instances

            #region Offsets
            foreach ($disk in $disks) {
                if (!$disk.name.StartsWith("\\")) {
                    $diskname = $disk.Name
                    if ($NoSqlCheck -eq $false) {
                        $sqldisk = $false

                        foreach ($instance in $SqlInstances) {
                            try {
                                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
                            } catch {
                                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
                            }

                            $sql = "SELECT COUNT(*) AS Count FROM sys.master_files WHERE physical_name LIKE '$diskname%'"
                            Write-Message -Level Verbose -Message "Query is: $sql" -FunctionName $FunctionName -ModuleName "dbatools"
                            Write-Message -Level Verbose -Message "SQL Server is: $instance." -FunctionName $FunctionName -ModuleName "dbatools"
                            $sqlcount = $server.Query($sql).Count
                            if ($sqlcount -gt 0) {
                                $sqldisk = $true
                                break
                            }
                        }
                    }

                    if ($NoSqlCheck -eq $false) {
                        if ($sqldisk -eq $true) {
                            $offsets += $disk
                        }
                    } else {
                        $offsets += $disk
                    }
                }
            }
            #endregion Offsets

            #region Processing results
            Write-Message -Level Verbose -Message "Checking $($offsets.count) partitions." -FunctionName $FunctionName -ModuleName "dbatools"
            foreach ($partition in $offsets) {
                # Unfortunately "Windows does not have a reliable way to determine stripe unit Sizes. These values are obtained from vendor disk management software or from your SAN administrator."
                # And this is the #1 most impactful issue with disk alignment :D
                # What we can do is test common stripe unit Sizes against the Offset we have and give advice if the Offset they chose would work in those scenarios
                $offset = $partition.StartingOffset / 1kb
                $type = $partition.Type
                $stripe_units = @(64, 128, 256, 512, 1024) # still wish I had a better way to verify this or someone to pat my back and say its alright.

                # testing dynamic disks, everyone states that info from dynamic disks is not to be trusted, so throw a warning.
                Write-Message -Level Verbose -Message "Testing for dynamic disks." -FunctionName $FunctionName -ModuleName "dbatools"
                if ($type -eq "Logical Disk Manager") {
                    $IsDynamicDisk = $true
                    Write-Message -Level Warning -Message "Disk is dynamic, all Offset calculations should be suspect, please refer to your vendor to determine actual Offset calculations." -FunctionName $FunctionName -ModuleName "dbatools"
                } else {
                    $IsDynamicDisk = $false
                }

                Write-Message -Level Verbose -Message "Checking for best practices offsets." -FunctionName $FunctionName -ModuleName "dbatools"

                if ($offset -ne 64 -and $offset -ne 128 -and $offset -ne 256 -and $offset -ne 512 -and $offset -ne 1024) {
                    $IsOffsetBestPractice = $false
                } else {
                    $IsOffsetBestPractice = $true
                }

                # as we can't tell the actual size of the file strip unit, just check all the sizes I know about
                foreach ($size in $stripe_units) {
                    if ($offset % $size -eq 0) {
                        # for proper alignment we really only need to know that your offset divided by your stripe unit size has a remainder of 0
                        $OffsetModuloKB = "$($offset % $size)"
                        $isBestPractice = $true
                    } else {
                        $OffsetModuloKB = "$($offset % $size)"
                        $isBestPractice = $false
                    }

                    [PSCustomObject]@{
                        ComputerName            = $ogComputer
                        Name                    = "$($partition.Name)"
                        PartitionSize           = [DbaSize]($($partition.Size / 1MB) * 1024 * 1024)
                        PartitionType           = $partition.Type
                        TestingStripeSize       = [DbaSize]($size * 1024)
                        OffsetModuluCalculation = [DbaSize]($OffsetModuloKB * 1024)
                        StartingOffset          = [DbaSize]($offset * 1024)
                        IsOffsetBestPractice    = $IsOffsetBestPractice
                        IsBestPractice          = $isBestPractice
                        NumberOfBlocks          = $partition.NumberOfBlocks
                        BootPartition           = $partition.BootPartition
                        PartitionBlockSize      = $partition.BlockSize
                        IsDynamicDisk           = $IsDynamicDisk
                    }
                }
            }
        }

        # uses cim commands


        foreach ($computer in $ComputerName) {
            $computer = $ogComputer = $computer.ComputerName
            Write-Message -Level VeryVerbose -Message "Processing: $computer." -FunctionName Test-DbaDiskAlignment -ModuleName "dbatools"

            $computer = Resolve-DbaNetworkName -ComputerName $computer -Credential $Credential
            $Computer = $computer.FullComputerName

            if (-not $Computer) {
                Stop-Function -Message "Couldn't resolve hostname. Skipping." -Continue -FunctionName Test-DbaDiskAlignment
            }

            #region Connecting to server via Cim
            Write-Message -Level Verbose -Message "Creating CimSession on $computer over WSMan" -FunctionName Test-DbaDiskAlignment -ModuleName "dbatools"

            if (-not $Credential) {
                $cimSession = New-CimSession -ComputerName $Computer -ErrorAction Ignore
            } else {
                $cimSession = New-CimSession -ComputerName $Computer -ErrorAction Ignore -Credential $Credential
            }

            if ($null -eq $cimSession.id) {
                Write-Message -Level Verbose -Message "Creating CimSession on $computer over WSMan failed. Creating CimSession on $computer over DCOM." -FunctionName Test-DbaDiskAlignment -ModuleName "dbatools"

                if (!$Credential) {
                    $cimSession = New-CimSession -ComputerName $Computer -SessionOption $sessionoption -ErrorAction Ignore
                } else {
                    $cimSession = New-CimSession -ComputerName $Computer -SessionOption $sessionoption -ErrorAction Ignore -Credential $Credential
                }
            }

            if ($null -eq $cimSession.id) {
                Stop-Function -Message "Can't create CimSession on $computer." -Target $Computer -Continue -FunctionName Test-DbaDiskAlignment
            }
            #endregion Connecting to server via Cim

            Write-Message -Level Verbose -Message "Getting Disk Alignment information from $Computer." -FunctionName Test-DbaDiskAlignment -ModuleName "dbatools"


            try {
                Get-DiskAlignment -CimSession $cimSession -NoSqlCheck $NoSqlCheck -ComputerName $Computer -FunctionName Test-DbaDiskAlignment -ErrorAction Stop
            } catch {
                Stop-Function -Message "Failed to process $($Computer): $($_.Exception.Message)" -Continue -InnerErrorRecord $_ -Target $Computer -FunctionName Test-DbaDiskAlignment
            }
        }

} $ComputerName $Credential $SqlCredential $NoSqlCheck $EnableException $sessionoption @__commonParameters 3>&1 2>&1
""";
}
