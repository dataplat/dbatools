function Remove-DbaClientAlias {
    <#
    .SYNOPSIS
    Removes a sql alias for the specified server - mimics cliconfg.exe

    .DESCRIPTION
    Removes a SQL Server alias by altering HKLM:\SOFTWARE\Microsoft\MSSQLServer\Client

    .PARAMETER ComputerName
    The target computer where the alias will be created

    .PARAMETER Credential
    Allows you to login to remote computers using alternative credentials

    .PARAMETER Alias
    The alias to be deleted

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
    https://dbatools.io/Remove-DbaClientAlias

    .EXAMPLE
    Remove-DbaClientAlias -ComputerName workstationx -Alias sqlps
    Removes the sqlps SQL client alias on workstationx

    .EXAMPLE
    Get-DbaClientAlias | Remove-DbaClientAlias
    Removes all SQL Server client aliases on the local computer

#>
    [CmdletBinding()]
    Param (
        [parameter(ValueFromPipelineByPropertyName)]
        [DbaInstanceParameter[]]$ComputerName = $env:COMPUTERNAME,
        [PSCredential]$Credential,
        [parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [Alias('AliasName')]
        [string]$Alias,
        [Alias('Silent')]
        [switch]$EnableException
    )

    process {

        foreach ($computer in $ComputerName) {
            $null = Test-ElevationRequirement -ComputerName $computer -Continue

            $scriptblock = {
                $Alias = $args[0]
                function Get-ItemPropertyValue {
                    Param (
                        [parameter()]
                        [String]$Path,
                        [parameter()]
                        [String]$Name
                    )
                    Get-ItemProperty -LiteralPath $Path -Name $Name
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


                    $all = Get-Item -Path $connect
                    foreach ($entry in $all) {

                        foreach ($en in $entry) {
                            $e = $entry.ToString().Replace('HKEY_LOCAL_MACHINE', 'HKLM:\')
                            if ($en.Property -contains $Alias) {
                                Remove-ItemProperty -Path $e -Name $Alias
                            }
                            else {
                                $en
                            }
                        }
                    }
                }
            }

            if ($PScmdlet.ShouldProcess($computer, "Getting aliases")) {
                try {
                    $null = Invoke-Command2 -ComputerName $computer -Credential $Credential -ScriptBlock $scriptblock -ErrorAction Stop -Verbose:$false -ArgumentList $Alias
                    Get-DbaClientAlias -ComputerName $computer

                }
                catch {
                    Stop-Function -Message "Failure" -ErrorRecord $_ -Target $computer -Continue
                }
            }
        }
    }
}