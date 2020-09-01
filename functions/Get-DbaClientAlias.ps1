function Get-DbaClientAlias {
    <#
    .SYNOPSIS
        Gets any SQL Server alias for the specified server(s)

    .DESCRIPTION
        Gets SQL Server alias by reading HKLM:\SOFTWARE\Microsoft\MSSQLServer\Client

    .PARAMETER ComputerName
        The target computer where the alias has been created

    .PARAMETER Credential
        Allows you to login to remote computers using alternative credentials

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Server, Management
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
                    [pscustomobject]@{
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