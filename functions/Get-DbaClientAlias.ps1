function Get-DbaClientAlias {
    <#
    .SYNOPSIS
    Creates/updates a sql alias for the specified server - mimics cliconfg.exe

    .DESCRIPTION
    Creates/updates a SQL Server alias by altering HKLM:\SOFTWARE\Microsoft\MSSQLServer\Client

    .PARAMETER ComputerName
    The target computer where the alias will be created

    .PARAMETER Credential
    Allows you to login to remote computers using alternative credentials

    .PARAMETER EnableException
    By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
    This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
    Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
    Tags: Alias

    Website: https://dbatools.io
    Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
    License: MIT https://opensource.org/licenses/MIT

    .LINK
    https://dbatools.io/Get-DbaClientAlias

        .EXAMPLE
    Get-DbaClientAlias
    Gets all SQL Server client aliases on the local computer

    .EXAMPLE
    Get-DbaClientAlias -ComputerName workstationx
    Gets all SQL Server client aliases on Workstationx
#>
    [CmdletBinding()]
    Param (
        [DbaInstanceParameter[]]$ComputerName = $env:COMPUTERNAME,
        [PSCredential]$Credential,
        [Alias('Silent')]
        [switch]$EnableException
    )

    process {
        foreach ($computer in $ComputerName) {
            $scriptblock = {

                function Get-ItemPropertyValue {
                    Param (
                        [parameter()]
                        [String]$Path,
                        [parameter()]
                        [String]$Name
                    )
                    (Get-ItemProperty -LiteralPath $Path -Name $Name).$Name
                }

                $basekeys = "HKLM:\SOFTWARE\WOW6432Node\Microsoft\MSSQLServer", "HKLM:\SOFTWARE\Microsoft\MSSQLServer"

                foreach ($basekey in $basekeys) {

                    if ((Test-Path $basekey) -eq $false) {
                        Write-Warning "Base key ($basekey) does not exist. Quitting."
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
                    }
                    else {
                        $architecture = "64-bit"
                    }

                    # "Creating/updating alias for $ComputerName for $architecture"
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

            if ($PScmdlet.ShouldProcess($computer, "Getting aliases")) {
                try {
                    Invoke-Command2 -ComputerName $computer -Credential $Credential -ScriptBlock $scriptblock -ErrorAction Stop |
                        Select-DefaultView -Property ComputerName, Architecture, NetworkLibrary, ServerName, AliasName
                }
                catch {
                    Stop-Function -Message "Failure" -ErrorRecord $_ -Target $computer -Continue
                }
            }
        }
    }
}