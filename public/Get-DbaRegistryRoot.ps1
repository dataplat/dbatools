function Get-DbaRegistryRoot {
    <#
    .SYNOPSIS
        Discovers Windows registry root paths for SQL Server instances to enable direct registry configuration access

    .DESCRIPTION
        Queries SQL Server WMI to locate the exact Windows registry hive path where each SQL Server instance stores its configuration settings. This eliminates the guesswork when you need to manually edit registry keys for troubleshooting startup issues, modifying trace flags, or automating configuration changes that aren't exposed through T-SQL or SQL Server Configuration Manager. The function handles both standalone instances and failover cluster instances, returning PowerShell-ready registry paths you can immediately use with Get-ItemProperty or Set-ItemProperty commands.

    .PARAMETER ComputerName
        Specifies the target computer where SQL Server instances are installed. Accepts computer names, IP addresses, or SQL Server instance names which will be parsed to extract the computer name.
        Use this when you need registry root paths for SQL Server instances on remote servers for configuration troubleshooting or automated registry modifications.

    .PARAMETER Credential
        Allows you to login to $ComputerName using alternative Windows credentials

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Management, OS, Registry
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaRegistryRoot

    .EXAMPLE
        PS C:\> Get-DbaRegistryRoot

        Gets the registry root for all instances on localhost

    .EXAMPLE
        PS C:\> Get-DbaRegistryRoot -ComputerName server1

        Gets the registry root for all instances on server1
    #>
    [CmdletBinding()]
    param (
        [parameter(ValueFromPipeline)]
        [DbaInstanceParameter[]]$ComputerName = $env:COMPUTERNAME,
        [PSCredential]$Credential,
        [switch]$EnableException
    )

    process {
        foreach ($computer in $computername) {
            try {
                $sqlwmis = Invoke-ManagedComputerCommand -ComputerName $computer.ComputerName -ScriptBlock { $wmi.Services } -Credential $Credential -ErrorAction Stop | Where-Object DisplayName -Match "SQL Server \("
            } catch {
                Stop-Function -Message $_ -Target $sqlwmi -Continue
            }

            foreach ($sqlwmi in $sqlwmis) {

                $regRoot = ($sqlwmi.AdvancedProperties | Where-Object Name -EQ REGROOT).Value
                $vsname = ($sqlwmi.AdvancedProperties | Where-Object Name -EQ VSNAME).Value
                $instanceName = $sqlwmi.DisplayName.Replace('SQL Server (', '').Replace(')', '') # Don't clown, I don't know regex :(

                if ([System.String]::IsNullOrEmpty($regRoot)) {
                    $regRoot = $sqlwmi.AdvancedProperties | Where-Object { $_ -match 'REGROOT' }
                    $vsname = $sqlwmi.AdvancedProperties | Where-Object { $_ -match 'VSNAME' }

                    if (![System.String]::IsNullOrEmpty($regRoot)) {
                        $regRoot = ($regRoot -Split 'Value\=')[1]
                        $vsname = ($vsname -Split 'Value\=')[1]
                    } else {
                        Stop-Function -Message "Can't find instance $instanceName on $env:COMPUTERNAME" -Continue
                    }
                }

                # vsname is the virtual server name for a failover cluster instance
                if ([System.String]::IsNullOrEmpty($vsname)) {
                    $sqlInstance = $computer.ComputerName
                } else {
                    $sqlInstance = $vsname
                }
                if ($instanceName -ne "MSSQLSERVER") {
                    $sqlInstance = "$sqlInstance\$instanceName"
                }

                Write-Message -Level Verbose -Message "Regroot: $regRoot"
                Write-Message -Level Verbose -Message "InstanceName: $instanceName"
                Write-Message -Level Verbose -Message "VSNAME: $vsname"

                [PSCustomObject]@{
                    ComputerName = $computer.ComputerName
                    InstanceName = $instanceName
                    SqlInstance  = $sqlInstance
                    Hive         = "HKLM"
                    Path         = $regRoot
                    RegistryRoot = "HKLM:\$regRoot"
                }
            }
        }
    }
}