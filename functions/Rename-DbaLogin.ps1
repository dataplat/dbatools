function Rename-DbaLogin {
    <#
.SYNOPSIS 
Rename-DbaLogin will rename login and database mapping for a specified login. 

.DESCRIPTION
There are times where you might want to rename a login that was copied down, or if the name is not descriptive for what it does. 

It can be a pain to update all of the mappings for a specific user, this does it for you. 

.PARAMETER SqlInstance
Source SQL Server.You must have sysadmin access and server version must be SQL Server version 2000 or greater.

.PARAMETER Destination
Destination Sql Server. You must have sysadmin access and server version must be SQL Server version 2000 or greater.

.PARAMETER SqlCredential 
Allows you to login to servers using SQL Logins as opposed to Windows Auth/Integrated/Trusted. To use:

$scred = Get-Credential, then pass $scred object to the -SourceSqlCredential parameter. 

Windows Authentication will be used if DestinationSqlCredential is not specified. SQL Server does not accept Windows credentials being passed as credentials. 	
To connect as a different Windows user, run PowerShell as that user.

.PARAMETER Login 
The current Login on the server - this list is auto-populated from the server.

.PARAMETER NewLogin 
The new Login that you wish to use. If it is a windows user login, then the SID must match.  

.PARAMETER Confirm
Prompts to confirm actions
		
.PARAMETER WhatIf
Shows what would happen if the command were to run. No actions are actually performed. 

.NOTES 
Tags: Login
Original Author: Mitchell Hamann (@SirCaptainMitch)

Website: https://dbatools.io
Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

.LINK
https://dbatools.io/Rename-DbaLogin

.EXAMPLE   
Rename-DbaLogin -SqlInstance localhost -Login DbaToolsUser -NewLogin captain

SQL Login Example 

.EXAMPLE   
Rename-DbaLogin -SqlInstance localhost -Login domain\oldname -NewLogin domain\newname

Change the windowsuser login name.

.EXAMPLE 
Rename-DbaLogin -SqlInstance localhost -Login dbatoolsuser -NewLogin captain -WhatIf

WhatIf Example
#>
    [CmdletBinding(DefaultParameterSetName = "Default", SupportsShouldProcess = $true)]
    param (
        [parameter(Mandatory = $true)]
        [DbaInstanceParameter]$SqlInstance,
        [PSCredential]$SqlCredential,
		[object]$Login,
        [parameter(Mandatory = $true)]
        [String]$NewLogin
    )
	
    begin {
		
        if (!$Login) { throw "You must specify a login" }
		
        $server = Connect-SqlInstance -SqlInstance $SqlInstance -SqlCredential $SqlCredential
        $Databases = $server.Databases
		
        $currentLogin = $server.Logins[$Login]
		
    }
    process {
        if ($Pscmdlet.ShouldProcess($SqlInstance, "Changing Login name from  [$Login] to [$NewLogin]")) {
            try {
                $dbenums = $currentLogin.EnumDatabaseMappings()
                $currentLogin.rename($NewLogin)
                [pscustomobject]@{
                    SqlInstance = $server.name
                    Database    = "N/A"
                    OldLogin    = $Login
                    NewLogin    = $NewLogin
                    Notes       = "Successfully renamed login"
                }
            }
            catch {
                $dbenums = $null
                [pscustomobject]@{
                    SqlInstance = $server.name
                    Database    = $null
                    OldLogin    = $Login
                    NewLogin    = $NewLogin
                    Notes       = "Failure to rename login"
                }
                Write-Exception $_
                continue
            }
        }
		
        foreach ($db in $dbenums) {
            $db = $databases[$db.DBName]
            $user = $db.Users[$Login]
            Write-Verbose "Starting update for $db"
			
            if ($Pscmdlet.ShouldProcess($SqlInstance, "Changing database $db user $user from [$Login] to [$NewLogin]")) {
                try {
                    $oldname = $user.name
                    $user.Rename($NewLogin)
                    [pscustomobject]@{
                        SqlInstance = $server.name
                        Database    = $db.name
                        OldUser     = $oldname
                        NewUser     = $NewLogin
                        Notes       = "Successfully renamed database user"
                    }
					
                }
                catch {
                    Write-Warning "Rolling back update to login: $Login"
                    $currentLogin.rename($Login)
					
                    [pscustomobject]@{
                        SqlInstance = $server.name
                        Database    = $db.name
                        OldUser     = $NewLogin
                        NewUser     = $oldname
                        Notes       = "Failure to rename. Rolled back change."
                    }
                    Write-Exception $_
                    break
                }
            }
        }
    }
}
