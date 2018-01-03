function Get-DbaSqlRegistryRoot {
    <#
.SYNOPSIS
Uses SQL WMI to find the Registry Root of each SQL Server instance on a computer

.DESCRIPTION
Uses SQL WMI to find the Registry Root of each SQL Server instance on a computer

.PARAMETER ComputerName
The target computer. This is not a SQL Server service, though if you pass a named SQL instance, it'll parse properly down to the computer name

.PARAMETER Credential
Allows you to login to $ComputerName using alternative Windows credentials

.PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

.NOTES
Tags: Configuration, Registry

Website: https://dbatools.io
Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

.EXAMPLE
Get-DbaSqlRegistryRoot
Gets the registry root for all instances on localhost

.EXAMPLE
Get-DbaSqlRegistryRoot -ComputerName server1

Gets the registry root for all instances on server1

#>
    [CmdletBinding()]
    param (
        [parameter(ValueFromPipeline)]
        [DbaInstanceParameter[]]$ComputerName = $env:COMPUTERNAME,
        [PSCredential]$Credential,
        [switch][Alias('Silent')]$EnableException
    )

    process {
        foreach ($computer in $computername) {
            Write-Message -Level Verbose -Message "Connecting to SQL WMI on $($computer.ComputerName)"
            try {
                $sqlwmis = Invoke-ManagedComputerCommand -ComputerName $computer.ComputerName -ScriptBlock { $wmi.Services } -Credential $Credential -ErrorAction Stop | Where-Object DisplayName -match "SQL Server \("
            }
            catch {
                Stop-Function -Message $_ -Target $sqlwmi -Continue
            }

            foreach ($sqlwmi in $sqlwmis) {

                $regroot = ($sqlwmi.AdvancedProperties | Where-Object Name -eq REGROOT).Value
                $vsname = ($sqlwmi.AdvancedProperties | Where-Object Name -eq VSNAME).Value
                $instancename = $sqlwmi.DisplayName.Replace('SQL Server (', '').Replace(')', '') # Don't clown, I don't know regex :(

                if ([System.String]::IsNullOrEmpty($regroot)) {
                    $regroot = $sqlwmi.AdvancedProperties | Where-Object { $_ -match 'REGROOT' }
                    $vsname = $sqlwmi.AdvancedProperties | Where-Object { $_ -match 'VSNAME' }

                    if (![System.String]::IsNullOrEmpty($regroot)) {
                        $regroot = ($regroot -Split 'Value\=')[1]
                        $vsname = ($vsname -Split 'Value\=')[1]
                    }
                    else {
                        Write-Message -Level Warning -Message "Can't find instance $vsname on $env:COMPUTERNAME"
                        return
                    }
                }

                # vsname takes care of clusters
                if ([System.String]::IsNullOrEmpty($vsname)) {
                    $vsname = $computer
                    if ($instancename -ne "MSSQLSERVER") {
                        $vsname = "$computer\$instancename"
                    }
                }

                Write-Message -Level Verbose -Message "Regroot: $regroot"
                Write-Message -Level Verbose -Message "InstanceName: $instancename"
                Write-Message -Level Verbose -Message "VSNAME: $vsname"

                [pscustomobject]@{
                    ComputerName = $computer.ComputerName
                    InstanceName = $instancename
                    SqlInstance  = $vsname
                    Hive         = "HKLM"
                    Path         = $regroot
                    RegistryRoot = "HKLM:\$regroot"
                }
            }
        }
    }
}