function Get-DbaClientAlias {
    <#
    .SYNOPSIS
        Retrieves SQL Server client aliases from the Windows registry on local or remote computers

    .DESCRIPTION
        Retrieves all configured SQL Server client aliases by reading the Windows registry paths where SQL Server Native Client stores alias definitions. Client aliases allow DBAs to create friendly names that map to actual SQL Server instances, making connection strings simpler and more portable across environments. This is particularly useful when managing multiple instances, non-default ports, or when you need to abstract the actual server names from applications and connection strings.

    .PARAMETER ComputerName
        Specifies the computer(s) to retrieve SQL Server client aliases from. Accepts multiple computers via pipeline input.
        Use this when you need to audit client alias configurations across multiple workstations or servers in your environment.

    .PARAMETER Credential
        Allows you to login to remote computers using alternative credentials

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: SqlClient, Alias
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaClientAlias

    .EXAMPLE
        PS C:\> Get-DbaClientAlias

        Gets all SQL Server client aliases on the local computer

    .EXAMPLE
        PS C:\> Get-DbaClientAlias -ComputerName workstationx

        Gets all SQL Server client aliases on Workstationx

    .EXAMPLE
        PS C:\> Get-DbaClientAlias -ComputerName workstationx -Credential ad\sqldba

        Logs into workstationx as ad\sqldba then retrieves all SQL Server client aliases on Workstationx

    .EXAMPLE
        PS C:\> 'Server1', 'Server2' | Get-DbaClientAlias

        Gets all SQL Server client aliases on Server1 and Server2
    #>
    [CmdletBinding()]
    param (
        [Parameter(ValueFromPipeline)]
        [DbaInstanceParameter[]]$ComputerName = $env:COMPUTERNAME,
        [PSCredential]$Credential,
        [switch]$EnableException
    )
    begin {
        $scriptBlock = {
            function Get-ItemPropertyValue {
                param (
                    [parameter()]
                    [String]$Path,
                    [parameter()]
                    [String]$Name
                )
                (Get-ItemProperty -LiteralPath $Path -Name $Name).$Name
            }

            $basekeys = "HKLM:\SOFTWARE\WOW6432Node\Microsoft\MSSQLServer", "HKLM:\SOFTWARE\Microsoft\MSSQLServer"

            foreach ($basekey in $basekeys) {

                <# DO NOT use Write-Message as this is inside of a scriptblock #>
                if ((Test-Path $basekey) -eq $false) {
                    continue
                }

                $client = "$basekey\Client"

                if ((Test-Path $client) -eq $false) {
                    continue
                }

                $connect = "$client\ConnectTo"

                if ((Test-Path $connect) -eq $false) {
                    continue
                }

                if ($basekey -like "*WOW64*") {
                    $architecture = "32-bit"
                } else {
                    $architecture = "64-bit"
                }

                # "Get SQL Server alias for $ComputerName for $architecture"
                $all = Get-Item -Path $connect
                foreach ($entry in $all.Property) {
                    $value = Get-ItemPropertyValue -Path $connect -Name $entry
                    $clean = $value.Replace('DBNMPNTW,', '').Replace('DBMSSOCN,', '')
                    if ($value.StartsWith('DBMSSOCN')) { $protocol = 'TCP/IP' } else { $protocol = 'Named Pipes' }
                    [PSCustomObject]@{
                        ComputerName   = $env:COMPUTERNAME
                        NetworkLibrary = $protocol
                        ServerName     = $clean
                        AliasName      = $entry
                        AliasString    = $value
                        Architecture   = $architecture
                    }
                }
            }
        }
    }
    process {
        foreach ($computer in $ComputerName) {
            try {
                Invoke-Command2 -ComputerName $computer -Credential $Credential -ScriptBlock $scriptBlock -ErrorAction Stop
            } catch {
                Stop-Function -Message "Failure" -ErrorRecord $_ -Target $computer -Continue
            }
        }
    }
}