function Set-DbaPrivilege {
  <#
      .SYNOPSIS
      Adds the SQL Service account to local privileges on one or more computers. 

      .DESCRIPTION
      Adds the SQL Service account to local privileges 'Lock Pages in Memory', 'Instant File Initialization', 'Logon as Batch' on one or more computers.

      Requires Local Admin rights on destination computer(s).

      .PARAMETER ComputerName
      The SQL Server (or server in general) that you're connecting to. This command handles named instances.

      .PARAMETER Credential
      Credential object used to connect to the computer as a different user.
	
	  .PARAMETER Silent 
	  Use this switch to disable any kind of verbose messages

      .NOTES
      Author: Klaas Vandenberghe ( @PowerDBAKlaas )
      Tags: Privilege
      Website: https://dbatools.io
	  Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
	  License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0
      
	.LINK
      https://dbatools.io/Set-DbaPrivilege

      .EXAMPLE
      Set-DbaPrivilege -ComputerName sqlserver2014a -LPIM -IFI

      Adds the SQL Service account(s) on computer sqlserver2014a to the local privileges 'SeManageVolumePrivilege' and 'SeLockMemoryPrivilege'.

      .EXAMPLE   
      'sql1','sql2','sql3' | Set-DbaPrivilege -IFI

      Adds the SQL Service account(s) on computers sql1, sql2 and sql3 to the local privilege 'SeManageVolumePrivilege'.

  #>
	[CmdletBinding()]
	Param (
		[parameter(ValueFromPipeline)]
		[Alias("cn", "host", "Server")]
		[dbainstanceparameter[]]$ComputerName = $env:COMPUTERNAME,
		[PSCredential][System.Management.Automation.CredentialAttribute()]
		$Credential,
        [switch]$IFI,
        [switch]$LPIM,
        [switch]$BatchLogon,
		[switch]$Silent
	)
	
	begin {
$ResolveAccountToSID = @"
function Convert-UserNameToSID ([string] `$Acc ) {
`$objUser = New-Object System.Security.Principal.NTAccount(`"`$Acc`")
`$strSID = `$objUser.Translate([System.Security.Principal.SecurityIdentifier])
`$strSID.Value
"@
		$ComputerName = $ComputerName.ComputerName | Select-Object -Unique
	}
	process {
		foreach ($computer in $ComputerName) {
			Write-Message -Level Verbose -Message "Connecting to $computer"
			if (Test-PSRemoting -ComputerName $Computer) {
				Write-Message -Level Verbose -Message "Exporting Privileges on $Computer"
				Invoke-Command2 -Raw -ComputerName $computer -Credential $Credential -ScriptBlock {
					$temp = ([System.IO.Path]::GetTempPath()).TrimEnd(""); secedit /export /cfg $temp\secpolByDbatools.cfg > $NULL;
				}
			    Write-Message -Level Verbose -Message "Getting SQL Service Accounts on $computer"
                $SQLServiceAccounts = (Get-DbaSqlService -ComputerName $computer -Type Engine).StartName
                if ( $SQLServiceAccounts.count -ge 1 ) {
                    Write-Message -Level Verbose -Message "Setting Privileges on $Computer"
				    Invoke-Command2 -Raw -ComputerName $computer -Credential $Credential -ArgumentList $ResolveAccountToSID, $SQLServiceAccounts, $BatchLogon, $IFI, $LPIM -ScriptBlock {
					    Param ($ResolveAccountToSID, $SQLServiceAccounts)
					    . ([ScriptBlock]::Create($ResolveAccountToSID))
					    $temp = ([System.IO.Path]::GetTempPath()).TrimEnd("");
                        $tempfile = "$temp\secpolByDbatools.cfg"
                        if ( $BatchLogon -eq $true ) {
					        $BLline = Get-Content $tempfile | Where-Object { $_ -match "SeBatchLogonRight" }
					        ForEach ( $acc in $SQLServiceAccounts ) {
                                $SID = Convert-UserNameToSID -Acc $acc;
                                if ( $BLline -notmatch $SID ) {
                                    (Get-Content $tempfile) -replace "SeBatchLogonRight = ","SeBatchLogonRight = *$SID" |
                                    Set-Content $tempfile
                                    Write-Message -Level Verbose -Message "Added $acc to Batch Logon Privileges on $Computer"
                                }
                                else {
                                    Write-Message -Level Warning -Message "$acc already has Batch Logon Privilege on $Computer"
                                }
                            }
                        }
                        if ( $IFI -eq $true ) {
					        $IFIline = Get-Content $tempfile | Where-Object { $_ -match "SeManageVolumePrivilege" }
					        ForEach ( $acc in $SQLServiceAccounts ) {
                                $SID = Convert-UserNameToSID -Acc $acc;
                                if ( $IFIline -notmatch $SID ) {
                                    (Get-Content $tempfile) -replace "SeManageVolumePrivilege = ","SeManageVolumePrivilege = *$SID" |
                                    Set-Content $tempfile
                                    Write-Message -Level Verbose -Message "Added $acc to Instant File Initialization Privileges on $Computer"
                                }
                                else {
                                    Write-Message -Level Warning -Message "$acc already has Instant File Initialization Privilege on $Computer"
                                }
                            }
                        }
                        if ( $LPIM -eq $true ) {
					        $LPIMline = Get-Content $tempfile | Where-Object { $_ -match "SeLockMemoryPrivilege" }
					        ForEach ( $acc in $SQLServiceAccounts ) {
                                $SID = Convert-UserNameToSID -Acc $acc;
                                if ( $LPIMline -notmatch $SID ) {
                                    (Get-Content $tempfile) -replace "SeLockMemoryPrivilege = ","SeLockMemoryPrivilege = *$SID" |
                                    Set-Content $tempfile
                                    Write-Message -Level Verbose -Message "Added $acc to Lock Pages in Memory Privileges on $Computer"
                                }
                                else {
                                    Write-Message -Level Warning -Message "$acc already has Lock Pages in Memory Privilege on $Computer"
                                }
                            }
                        }
                        secedit /import /cfg $tempfile /overwrite /quiet
				    } -ErrorAction SilentlyContinue
				    Write-Message -Level Verbose -Message "Removing secpol file on $computer"
				    Invoke-Command2 -Raw -ComputerName $computer -Credential $Credential -ScriptBlock { $temp = ([System.IO.Path]::GetTempPath()).TrimEnd(""); Remove-Item $temp\secpolByDbatools.cfg -Force > $NULL }
			    }
                else {
                    Write-Message -Level Warning -Message "No SQL Service Accounts found on $Computer"
                }
            }
			else {
				Write-Message -Level Warning -Message "Failed to connect to $Computer"
			}
		}
	}
}