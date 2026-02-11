function Test-DbaDiskAllocation {
    <#
    .SYNOPSIS
        Validates disk allocation unit sizes against SQL Server best practice recommendations.

    .DESCRIPTION
        Examines all NTFS volumes on target servers to verify they are formatted with 64KB allocation units, which is the recommended cluster size for optimal SQL Server performance. When checking a single server, returns a simple true/false result. For multiple servers, returns detailed information including server name, disk details, and compliance status for each volume.

        The function can automatically detect SQL Server instances and identify which disks contain database files, helping you focus on storage that directly impacts SQL Server performance. System drives are automatically excluded from best practice validation since they typically don't require the 64KB allocation unit size.

        This validation is essential during SQL Server deployment planning and storage configuration audits, as improper allocation unit sizes can significantly impact database I/O performance.

        References:
        https://technet.microsoft.com/en-us/library/dd758814(v=sql.100).aspx - "The performance question here is usually not one of correlation per the formula, but whether the cluster size has been explicitly defined at 64 KB, which is a best practice for SQL Server."

    .PARAMETER ComputerName
        Specifies the target server(s) to examine for disk allocation unit compliance. Accepts multiple server names for bulk validation.
        Use this to verify storage configuration across your SQL Server environment during deployment or storage audits.

    .PARAMETER NoSqlCheck
        Skips detection of SQL Server database files and examines all NTFS volumes regardless of their SQL Server usage.
        Use this when you want to validate allocation units on all drives, not just those containing SQL Server data or log files.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Credential
        Specifies an alternate Windows account to use when enumerating drives on the server. May require Administrator privileges. To use:

        $cred = Get-Credential, then pass $cred object to the -Credential parameter.

    .PARAMETER WhatIf
        If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

    .PARAMETER Confirm
        If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Storage, Disk, OS
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .OUTPUTS
        PSCustomObject

        Returns one object per NTFS volume found on the target server.

        Default display properties via Select-DefaultView (when -NoSqlCheck is not specified):
        - ComputerName: Computer name of the target server
        - DiskName: Drive letter or volume name (e.g., "C:", "D:")
        - DiskLabel: Volume label or name assigned to the drive
        - BlockSize: Allocation unit size in bytes (65536 = 64KB is best practice)
        - IsSqlDisk: Boolean indicating if the volume contains SQL Server database or log files
        - IsBestPractice: Boolean indicating if BlockSize equals 65536 (64KB) - false for system drives

        When -NoSqlCheck is specified, the IsSqlDisk property is omitted from default display:
        - ComputerName: Computer name of the target server
        - DiskName: Drive letter or volume name
        - DiskLabel: Volume label
        - BlockSize: Allocation unit size in bytes
        - IsBestPractice: Boolean indicating if BlockSize equals 65536 (64KB)

        Alias properties for backwards compatibility:
        - Server: Alias for ComputerName
        - Name: Alias for DiskName
        - Label: Alias for DiskLabel

    .LINK
        https://dbatools.io/Test-DbaDiskAllocation

    .EXAMPLE
        PS C:\> Test-DbaDiskAllocation -ComputerName sqlserver2014a

        Scans all disks on server sqlserver2014a for best practice allocation unit size.

    .EXAMPLE
        PS C:\> Test-DbaDiskAllocation -ComputerName sqlserver2014 | Select-Output *

        Scans all disks on server sqlserver2014a for allocation unit size and returns detailed results for each.

    .EXAMPLE
        PS C:\> Test-DbaDiskAllocation -ComputerName sqlserver2014a -NoSqlCheck

        Scans all disks not hosting SQL Server data or log files on server sqlserver2014a for best practice allocation unit size.

    #>
    [CmdletBinding()]
    [OutputType("System.Collections.ArrayList", "System.Boolean")]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [object[]]$ComputerName,
        [switch]$NoSqlCheck,
        [PSCredential]$SqlCredential,
        [PSCredential]$Credential,
        [switch]$EnableException
    )

    begin {
        $sessionoptions = New-CimSessionOption -Protocol DCOM
    }

    process {
        foreach ($computer in $ComputerName) {
            $fullComputerName = Resolve-DbaComputerName -ComputerName $computer -Credential $Credential

            if (!$fullComputerName) {
                Stop-Function -Message "Couldn't resolve hostname $computer. Skipping." -Continue
            }

            Write-Message -Level Verbose -Message "Creating CimSession on $fullComputerName over WSMan."

            if (!$Credential) {
                $cimSession = New-CimSession -ComputerName $fullComputerName -ErrorAction SilentlyContinue
            } else {
                $cimSession = New-CimSession -ComputerName $fullComputerName -ErrorAction SilentlyContinue -Credential $Credential
            }

            if ($null -eq $cimSession.id) {
                Write-Message -Level Verbose -Message "Creating CimSession on $fullComputerName over WSMan failed. Creating CimSession on $fullComputerName over DCOM."

                if (!$Credential) {
                    $cimSession = New-CimSession -ComputerName $fullComputerName -SessionOption $sessionoptions -ErrorAction SilentlyContinue
                } else {
                    $cimSession = New-CimSession -ComputerName $fullComputerName -SessionOption $sessionoptions -ErrorAction SilentlyContinue -Credential $Credential
                }
            }

            if ($null -eq $cimSession.id) {
                Stop-Function -Message "Can't create CimSession on $fullComputerName" -Target $computer
            }

            Write-Message -Level Verbose -Message "Getting Disk Allocation from $computer"

            try {
                Write-Message -Level Verbose -Message "Getting disk information from $computer."
                $disks = Get-CimInstance -CimSession $cimSession -ClassName win32_volume -Filter "FileSystem='NTFS'" -ErrorAction Stop | Sort-Object -Property Name
            } catch {
                Stop-Function -Message "Can't connect to WMI on $computer."
                return
            }

            if ($NoSqlCheck -eq $false) {
                Write-Message -Level Verbose -Message "Checking for SQL Services"
                $sqlInstances = (Get-DbaService -ComputerName $fullComputerName -Type Engine -AdvancedProperties | Where-Object State -eq Running | Sort-Object -Property Name).SqlInstance
                Write-Message -Level Verbose -Message "$($sqlInstances.Count) instance(s) found."
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
                                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
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
    }
}