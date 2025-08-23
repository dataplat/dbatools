function Get-DbaPrivilege {
    <#
    .SYNOPSIS
        Retrieves Windows security privileges critical for SQL Server performance from target computers.

    .DESCRIPTION
        Audits five Windows privileges that directly impact SQL Server performance and functionality: Lock Pages in Memory, Instant File Initialization, Logon as Batch, Generate Security Audits, and Logon as a Service. These privileges are essential for SQL Server service accounts to achieve optimal performance and proper operation.

        Use this to verify that SQL Server service accounts have the necessary Windows privileges configured, troubleshoot performance issues related to missing privileges, or audit security configurations across your SQL Server environment. The function exports the local security policy using secedit and parses the results to show which users and groups hold these critical privileges.

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
        Tags: Privilege, OS, Security
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
        function Convert-SIDToUserName ([string] $SID ) {
            try {
                $objSID = New-Object System.Security.Principal.SecurityIdentifier ($SID)
                $objUser = $objSID.Translate([System.Security.Principal.NTAccount])
                $objUser.Value
            } catch {
                $SID
            }
        }

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
                Write-Message -Level Verbose -Message "Exporting Privileges on $computer and cleaning up temporary files"
                $secPol = Invoke-Command2 -Raw -ComputerName $computer -Credential $Credential -ScriptBlock {
                    $temp = ([System.IO.Path]::GetTempPath()).TrimEnd("")
                    secedit /export /cfg $temp\secpolByDbatools.cfg > $null
                    $CFG = Get-Content $temp\secpolByDbatools.cfg -Force
                    Remove-Item $temp\secpolByDbatools.cfg -Force
                    $CFG
                }

                Write-Message -Level Verbose -Message "Getting Batch Logon Privileges on $computer"
                $blEntries = $secPol | Where-Object { $_ -like "SeBatchLogonRight*" }

                $bl = if ($null -ne $blEntries) {
                    $blEntries.Substring(20).Split(",") | ForEach-Object {
                        if ($_ -match '^\*S-') {
                            Convert-SIDToUserName -SID $_.TrimStart('*')
                        } else {
                            $_
                        }
                    }
                }

                if ($bl.count -eq 0) {
                    Write-Message -Level Verbose -Message "No users with Batch Logon Rights on $computer"
                }

                Write-Message -Level Verbose -Message "Getting Instant File Initialization Privileges on $computer"
                $ifiEntries = $secPol | Where-Object { $_ -like 'SeManageVolumePrivilege*' }

                $ifi = if ($null -ne $ifiEntries) {
                    $ifiEntries.Substring(26).Split(",") | ForEach-Object {
                        if ($_ -match '^\*S-') {
                            Convert-SIDToUserName -SID $_.TrimStart('*')
                        } else {
                            $_
                        }
                    }
                }

                if ($ifi.count -eq 0) {
                    Write-Message -Level Verbose -Message "No users with Instant File Initialization Rights on $computer"
                }

                Write-Message -Level Verbose -Message "Getting Lock Pages in Memory Privileges on $computer"
                $lpimEntries = $secPol | Where-Object { $_ -like 'SeLockMemoryPrivilege*' }

                $lpim = if ($null -ne $lpimEntries) {
                    $lpimEntries.Substring(24).Split(",") | ForEach-Object {
                        if ($_ -match '^\*S-') {
                            Convert-SIDToUserName -SID $_.TrimStart('*')
                        } else {
                            $_
                        }
                    }
                }

                if ($lpim.count -eq 0) {
                    Write-Message -Level Verbose -Message "No users with Lock Pages in Memory Rights on $computer"
                }

                Write-Message -Level Verbose -Message "Getting Generate Security Audits Privileges on $computer"
                $gsaEntries = $secPol | Where-Object { $_ -like 'SeAuditPrivilege*' }

                $gsa = if ($null -ne $gsaEntries) {
                    $gsaEntries.Substring(19).Split(",") | ForEach-Object {
                        if ($_ -match '^\*S-') {
                            Convert-SIDToUserName -SID $_.TrimStart('*')
                        } else {
                            $_
                        }
                    }
                }

                if ($gsa.count -eq 0) {
                    Write-Message -Level Verbose -Message "No users with Generate Security Audits Rights on $computer"
                }

                Write-Message -Level Verbose -Message "Getting Logon as a service Privileges on $computer"
                $losEntries = $secPol | Where-Object { $_ -like "SeServiceLogonRight*" }

                $los = if ($null -ne $losEntries) {
                    $losEntries.Substring(22).split(",") | ForEach-Object {
                        if ($_ -match '^\*S-') {
                            Convert-SIDToUserName -SID $_.TrimStart('*')
                        } else {
                            $_
                        }
                    }
                }

                if ($los.count -eq 0) {
                    Write-Message -Level Verbose -Message "No users with Logon as a service Rights on $computer"
                }

                $users = @() + $bl + $ifi + $lpim + $gsa + $los | Select-Object -Unique
                $users | ForEach-Object {
                    [PSCustomObject]@{
                        ComputerName              = $computer
                        User                      = $_
                        LogonAsBatch              = $bl -contains $_
                        InstantFileInitialization = $ifi -contains $_
                        LockPagesInMemory         = $lpim -contains $_
                        GenerateSecurityAudit     = $gsa -contains $_
                        LogonAsAService           = $los -contains $_
                    }
                }

            } catch {
                Stop-Function -Continue -Message "Failure" -ErrorRecord $_ -Target $computer
            }
        }
    }
}