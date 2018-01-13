function New-DbaDbUser {
	<#
		.SYNOPSIS
			Creates a new user for the specified database.
		.DESCRIPTION
			Created a new user for a specified database with provided specifications.
		.PARAMETER SqlInstance
			The target SQL Server instance. Defaults to the default instance on localhost.
		.PARAMETER SqlCredential
			Allows you to login to servers using SQL Logins instead of Windows Authentication (AKA Integrated or Trusted). To use:

			$scred = Get-Credential, then pass $scred object to the -SqlCredential parameter.

			Windows Authentication will be used if SqlCredential is not specified. SQL Server does not accept Windows credentials being passed as credentials.

			To connect to SQL Server as a different Windows user, run PowerShell as that user.
		.PARAMETER Database
			Specifies the database(s) to process. Options for this list are auto-populated from the server. If unspecified, all databases will be processed.
		.PARAMETER ExcludeDatabase
			Specifies the database(s) to exclude from processing. Options for this list are auto-populated from the server. By default, system databases are excluded.
		.PARAMETER IncludeSystem
			If this switch is enabled, the user will be added to system databases.
		.PARAMETER Login
			When specified, the user will be associated to this SQL login and have the same name as the Login. Username or Login may be specified but not both.
		.PARAMETER Username
			When specified, the user will have this name. Username or Login may be specified but not both.
		.PARAMETER Force
			If user exists, drop and recreate.
		.PARAMETER WhatIf
			If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.
		.PARAMETER Confirm
			If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.
		.PARAMETER EnableException
			By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
			This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
			Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

		.NOTES
			Tags: Database, User
			Author: Frank Henninger (@osiris687)
			Website: https://dbatools.io
			Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
			License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0
		.LINK
			https://dbatools.io/New-DbaDbUser

		.EXAMPLE
		New-DbaDbUser -SqlInstance sqlserver2014 -Database DB1 -Login user1
		Creates a new sql user with login named user1 in the specified database

		.EXAMPLE
		New-DbaDbUser -SqlInstance sqlserver2014 -Database DB1 -Username user1
		Creates a new sql user without login named user1 in the specified database

		.EXAMPLE
		Get-DbaDatabaseUser -SqlInstance sqlserver1 -Database DB1 | New-DbaDbUser -SqlInstance sqlserver2 -Database DB1
		Copies users from sqlserver1.DB1 to sqlserver2.DB1. Does not copy permissions!

	#>
    [CmdletBinding(SupportsShouldProcess = $true, DefaultParameterSetName = "NoLogin")]
    param (
        [parameter(Mandatory, Position = 1)]
        [Alias("ServerInstance", "SqlServer")]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [Alias("Databases")]
        [object[]]$Database,
        [object[]]$ExcludeDatabase,
        [switch]$IncludeSystem,
        [Alias("Name", "LoginName")]
        [parameter(ParameterSetName = "Login")]
        [string[]]$Login,
        # [parameter(ParameterSetName = "Contained")]

        [parameter(ParameterSetName = "Login")]
        [parameter(ParameterSetName = "NoLogin")]
        [string[]]$Username,
        # [parameter(ParameterSetName = "Contained")]

        # [Security.SecureString]$Password,

        [switch]$Force,
        [switch][Alias('Silent')]
        $EnableException
    )
    
    begin {
        
        
    }
    process {
        foreach ($instance in $SqlInstance) {
            try {
                Write-Message -Level Verbose -Message "Connecting to $instance"
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $sqlcredential
            }
            catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
                return
            }
            
            $databases = $server.Databases | Where-Object Status -EQ "normal"
            
            if ($Database) {
                $databases = $databases | Where-Object Name -In $Database
            }
            if ($ExcludeDatabase) {
                $databases = $databases | Where-Object Name -NotIn $ExcludeDatabase
            }
            If (-Not $IncludeSystem) {
                $databases = $databases | Where-Object IsSystemObject -NE $true
            }
            
            
            foreach ($db in $databases) {
                Write-Message -Level Verbose -Message "Add users to Database $db on target $server";
                
                switch ($PSCmdlet.ParameterSetName) {
                    "Login" {
                        # Creates a user with Login
                        Write-Message -Level Verbose -Message "Using UserType: SqlLogin"
                        
                        if ($PSBoundParameters.Keys -notcontains 'Login') {
                            Stop-Function -Message "Parameter -Login is required " -Target $instance
                            return
                        }
                        
                        
                        if ($Login.GetType().Name -eq 'Login') {
                            $smoLogin = $Login
                        }
                        else {
                            #get the login associated with the given name.
                            $smoLogin = $server.Logins | Where-Object Name -eq $Login
                            if ($smoLogin -eq $null) { Stop-Function -Message "Invalid Login: $Login is not found on $Server" -Target $instance; return }
                        }
                        
                        # Does user exist with same login?
                        if ($existingUser = ($db.Users | Where-Object Login -eq $smoLogin)) {
                            if ($force) {
                                if ($Pscmdlet.ShouldProcess($existingUser, "Dropping existing user $($existingUser.Name) because -Force was used")) {
                                    try {
                                        $existingUser.Drop()
                                    }
                                    catch {
                                        Stop-Function -Message "Could not remove existing user $($existingUser.Name), skipping." -Target $existingUser -Continue
                                        return
                                    }
                                }
                            }
                            else {
                                Stop-Function -Message "User $($existingUser.Name) already exists and -Force was not specified" -Target $existingUser
                                return
                            }
                        }
                        
                        $Login = $smoLogin
                        $Name = $smoLogin.Name;
                        $UserType = [Microsoft.SqlServer.Management.Smo.UserType]::SqlLogin
                        
                    }
                    
                    # "Contained" {
                    #     # creates a user with password in a contained database
                    #     Write-Message -Level Verbose -Message "Using ParamaterSetName: Contained"
                    #     # Is this database contained?
                    #     If($db.ContainmentType -ne "Partial" ){
                    #         Stop-Function -Message "Sql User's with passwords can only be created on partially contained databases."  -Category InvalidOperation -Target $instance;
                    #         return
                    #     } else {
                    #         Write-Message -Level Verbose -Message $db.ContainmentType
                    #     }
                    
                    
                    #     $UserType = [Microsoft.SqlServer.Management.Smo.UserType]::SqlUser
                    
                    # }
                    
                    "NoLogin" {
                        # Creates a user without login
                        Write-Message -Level Verbose -Message "Using UserType: NoLogin"
                        $UserType = [Microsoft.SqlServer.Management.Smo.UserType]::NoLogin
                        $Name = $Username;
                    }
                } #switch
                
                # Does user exist with same name?
                if ($existingUser = $db.Users[$Name]) {
                    if ($force) {
                        if ($Pscmdlet.ShouldProcess($existingUser, "Dropping existing user $Name because -Force was used")) {
                            try {
                                $existingUser.Drop()
                            }
                            catch {
                                Stop-Function -Message "Could not remove existing user $Name, skipping." -Target $Name -Continue
                                return
                            }
                        }
                    }
                    else {
                        Stop-Function -Message "User $Name already exists and -Force was not specified" -Target $Name
                        return
                    }
                }
                
                
                if ($Pscmdlet.ShouldProcess($db, "Creating user $Name")) {
                    try {
                        $smoUser = New-Object Microsoft.SqlServer.Management.Smo.User;
                        $smoUser.Parent = $db;
                        $smoUser.Name = $Name;
                        
                        If ($PSBoundParameters.Keys -contains 'Login' -and $Login.GetType().Name -eq 'Login') { $smoUser.Login = Login }
                        $smoUser.UserType = $UserType;
                        
                        $smoUser.Create();
                        
                    }
                    catch {
                        Stop-Function -Message "Failed to add user $Name in $db to $instance" -Category InvalidOperation -ErrorRecord $_ -Target $instance -Continue;
                        return
                    }
                    $smoUser.Refresh();
                    
                    if ($PSBoundParameters.Keys -contains 'Username' -and $smoUser.Name -ne $Username) {
                        $smoUser.Rename($Username);
                    }
                    
                    # if ( $PSBoundParameters.Keys -contains 'Password' ) {
                    #     $smoUser.ChangePassword('',$Password);
                    #     $smoUser.Alter();
                    #     $smoUser.Refresh();
                    # }
                    
                    Write-Message -Level Verbose -Message "Successfully added $smoUser in $db to $instance."
                    
                }
                
                #Display Results
                Get-DbaDatabaseUser -SqlInstance $server.Name -Database $db.Name | Where-Object name -eq $smoUser.Name
            } #foreach ($db in $databases)
        } #foreach ($instance in $SqlInstance)
    }
    end {
        if (Test-FunctionInterrupt) { return }
    }
}
