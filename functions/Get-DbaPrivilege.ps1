function Get-DbaPrivilege {
    <#
    .SYNOPSIS
        Gets the users with local privileges on one or more computers.

    .DESCRIPTION
        Gets the users with local privileges 'Lock Pages in Memory', 'Instant File Initialization', 'Logon as Batch', or 'Generate Security Audits' on one or more computers.

        Requires Local Admin rights on destination computer(s).

    .PARAMETER ComputerName
        The target SQL Server instance or instances.

    .PARAMETER Credential
        Credential object used to connect to the computer as a different user.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Privilege
        Author: Klaas Vandenberghe (@PowerDBAKlaas)

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaPrivilege

    .EXAMPLE
        PS C:\> Get-DbaPrivilege -ComputerName sqlserver2014a

        Gets the local privileges on computer sqlserver2014a.

    .EXAMPLE
        PS C:\> 'sql1','sql2','sql3' | Get-DbaPrivilege

        Gets the local privileges on computers sql1, sql2 and sql3.

    .EXAMPLE
        PS C:\> Get-DbaPrivilege -ComputerName sql1,sql2 | Out-GridView

        Gets the local privileges on computers sql1 and sql2, and shows them in a grid view.

    #>
    [CmdletBinding()]
    param (
        [parameter(ValueFromPipeline)]
        [Alias("cn", "host", "Server")]
        [DbaInstanceParameter[]]$ComputerName = $env:COMPUTERNAME,
        [PSCredential]$Credential,
        [switch]$EnableException
    )

    begin {
        $ResolveSID = @"
    function Convert-SIDToUserName ([string] `$SID ) {
      `$objSID = New-Object System.Security.Principal.SecurityIdentifier (`"`$SID`")
      `$objUser = `$objSID.Translate( [System.Security.Principal.NTAccount])
      `$objUser.Value
    }
"@
        $ComputerName = $ComputerName.ComputerName | Select-Object -Unique
    }
    process {
        foreach ($computer in $ComputerName) {
            try {
                $null = Test-PSRemoting -ComputerName $Computer -EnableException
            } catch {
                Stop-Function -Message "Failure on $computer" -ErrorRecord $_ -Continue
            }

            try {
                Write-Message -Level Verbose -Message "Getting Privileges on $Computer"
                $Priv = $null
                $Priv = Invoke-Command2 -Raw -ComputerName $computer -Credential $Credential -ScriptBlock {
                    $temp = ([System.IO.Path]::GetTempPath()).TrimEnd(""); secedit /export /cfg $temp\secpolByDbatools.cfg > $NULL;
                    Get-Content $temp\secpolByDbatools.cfg | Where-Object {
                        $_ -match "SeBatchLogonRight" -or
                        $_ -match 'SeManageVolumePrivilege' -or
                        $_ -match 'SeLockMemoryPrivilege' -or
                        $_ -match 'SeAuditPrivilege'
                    }
                }
                if ($Priv.count -eq 0) {
                    Write-Message -Level Verbose -Message "No users with Batch Logon, Instant File Initialization, Lock Pages in Memory Rights, or Generate Security Audits on $computer"
                }

                Write-Message -Level Verbose -Message "Getting Batch Logon Privileges on $Computer"
                $BL = Invoke-Command2 -Raw -ComputerName $computer -Credential $Credential -ArgumentList $ResolveSID -ScriptBlock {
                    param ($ResolveSID)
                    . ([ScriptBlock]::Create($ResolveSID))
                    $temp = ([System.IO.Path]::GetTempPath()).TrimEnd("");
                    $blEntries = (Get-Content $temp\secpolByDbatools.cfg | Where-Object {
                            $_ -like "SeBatchLogonRight*"
                        })

                    if ($null -ne $blEntries) {
                        $blEntries.substring(20).split(",").replace("`*", "") | ForEach-Object {
                            Convert-SIDToUserName -SID $_
                        }
                    }

                } -ErrorAction SilentlyContinue
                if ($BL.count -eq 0) {
                    Write-Message -Level Verbose -Message "No users with Batch Logon Rights on $computer"
                }

                Write-Message -Level Verbose -Message "Getting Instant File Initialization Privileges on $Computer"
                $ifi = Invoke-Command2 -Raw -ComputerName $computer -Credential $Credential -ArgumentList $ResolveSID -ScriptBlock {
                    param ($ResolveSID)
                    . ([ScriptBlock]::Create($ResolveSID))
                    $temp = ([System.IO.Path]::GetTempPath()).TrimEnd("");
                    $ifiEntries = (Get-Content $temp\secpolByDbatools.cfg | Where-Object {
                            $_ -like 'SeManageVolumePrivilege*'
                        })

                    if ($null -ne $ifiEntries) {
                        $ifiEntries.substring(26).split(",").replace("`*", "") | ForEach-Object {
                            Convert-SIDToUserName -SID $_
                        }
                    }

                } -ErrorAction SilentlyContinue
                if ($ifi.count -eq 0) {
                    Write-Message -Level Verbose -Message "No users with Instant File Initialization Rights on $computer"
                }

                Write-Message -Level Verbose -Message "Getting Lock Pages in Memory Privileges on $Computer"
                $lpim = Invoke-Command2 -Raw -ComputerName $computer -Credential $Credential -ArgumentList $ResolveSID -ScriptBlock {
                    param ($ResolveSID)
                    . ([ScriptBlock]::Create($ResolveSID))
                    $temp = ([System.IO.Path]::GetTempPath()).TrimEnd("");
                    $lpimEntries = (Get-Content $temp\secpolByDbatools.cfg | Where-Object {
                            $_ -like 'SeLockMemoryPrivilege*'
                        })

                    if ($null -ne $lpimEntries) {
                        $lpimEntries.substring(24).split(",").replace("`*", "") | ForEach-Object {
                            Convert-SIDToUserName -SID $_
                        }
                    }
                } -ErrorAction SilentlyContinue

                if ($lpim.count -eq 0) {
                    Write-Message -Level Verbose -Message "No users with Lock Pages in Memory Rights on $computer"
                }

                Write-Message -Level Verbose -Message "Getting Generate Security Audits Privileges on $Computer"
                $gsa = Invoke-Command2 -Raw -ComputerName $computer -Credential $Credential -ArgumentList $ResolveSID -ScriptBlock {
                    param ($ResolveSID)
                    . ([ScriptBlock]::Create($ResolveSID))
                    $temp = ([System.IO.Path]::GetTempPath()).TrimEnd("");
                    $gsaEntries = (Get-Content $temp\secpolByDbatools.cfg | Where-Object {
                            $_ -like 'SeAuditPrivilege*'
                        })

                    if ($null -ne $gsaEntries) {
                        $gsaEntries.substring(19).split(",").replace("`*", "") | ForEach-Object {
                            Convert-SIDToUserName -SID $_
                        }
                    }
                } -ErrorAction SilentlyContinue

                if ($gsa.count -eq 0) {
                    Write-Message -Level Verbose -Message "No users with Generate Security Audits Rights on $computer"
                }
                $users = @() + $BL + $ifi + $lpim + $gsa | Select-Object -Unique
                $users | ForEach-Object {
                    [PSCustomObject]@{
                        ComputerName              = $computer
                        User                      = $_
                        LogonAsBatch              = $BL -contains $_
                        InstantFileInitialization = $ifi -contains $_
                        LockPagesInMemory         = $lpim -contains $_
                        GenerateSecurityAudit     = $gsa -contains $_
                    }
                }
                Write-Message -Level Verbose -Message "Removing secpol file on $computer"
                Invoke-Command2 -Raw -ComputerName $computer -Credential $Credential -ScriptBlock {
                    $temp = ([System.IO.Path]::GetTempPath()).TrimEnd(""); Remove-Item $temp\secpolByDbatools.cfg -Force > $NULL
                }
            } catch {
                Stop-Function -Continue -Message "Failure" -ErrorRecord $_ -Target $computer
            }
        }
    }
}
