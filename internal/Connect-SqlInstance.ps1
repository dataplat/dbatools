Function Connect-SqlInstance
{
    <#
        .SYNOPSIS
            Internal function to establish smo connections.
        
        .DESCRIPTION
            Internal function to establish smo connections.
    
            Can interpret any of the following types of information:
            - String
            - Smo Server objects
            - Smo Linked Server objects
        
        .PARAMETER SqlInstance
            The SQL Server instance to restore to.

        .PARAMETER SqlCredential
            Allows you to login to servers using SQL Logins as opposed to Windows Auth/Integrated/Trusted. 
        
        .PARAMETER ParameterConnection
            Whether this call is for dynamic parameters only.
        
        .PARAMETER RegularUser
            The connection doesn't require SA privileges.
            By default, the assumption is that SA is required.
        
        .EXAMPLE
            Connect-SqlInstance -SqlInstance sql2014
    
            Connect to the Server sql2014 with native credentials.
    #>
    
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [Object]
        $SqlInstance,
        
        [object]
        $SqlCredential,
        
        [switch]
        $ParameterConnection,
        
        [switch]
        $RegularUser
    )
    
    
    #region Ensure Credential integrity
    <#
    Usually, the parameter type should have been not object but off the PSCredential type.
    When binding null to a PSCredential type parameter on PS3-4, it'd then show a prompt, asking for username and password.
    
    In order to avoid that and having to refactor lots of functions (and to avoid making regular scripts harder to read), we created this workaround.
    #>
    if ($SqlCredential)
    {
        if ($SqlCredential.GetType() -ne [System.Management.Automation.PSCredential])
        {
            throw "The credential parameter was of a non-supported type! Only specify PSCredentials such as generated from Get-Credential. Input was of type $($SqlCredential.GetType().FullName)"
        }
    }
    #endregion Ensure Credential integrity
    
    #region Safely convert input into instance parameters
    <#
    This is a bit ugly, but:
    In some cases functions would directly pass their own input through when the parameter on the calling function was typed as [object[]].
    This would break the base parameter class, as it'd automatically be an array and the parameterclass is not designed to handle arrays (Shouldn't have to).
    
    Note: Multiple servers in one call were never supported, those old functions were liable to break anyway and should be fixed soonest.
    #>
    if ($SqlInstance.GetType() -eq [SqlCollective.Dbatools.Parameter.DbaInstanceParameter])
    {
        [DbaInstanceParameter]$ConvertedSqlInstance = $SqlInstance
    }
    else
    {
        [DbaInstanceParameter]$ConvertedSqlInstance = [DbaInstanceParameter]($SqlInstance | Select-Object -First 1)
        
        if ($SqlInstance.Count -gt 1)
        {
            Write-Message -Level Warning -Silent $true -Message "More than on server was specified when calling Connect-SqlInstance from $((Get-PSCallStack)[1].Command)"
        }
    }
    #endregion Safely convert input into instance parameters
    
    #region Input Object was a server object
    if ($ConvertedSqlInstance.InputObject.GetType() -eq [Microsoft.SqlServer.Management.Smo.Server])
    {
        $server = $ConvertedSqlInstance.InputObject
        if ($ParameterConnection)
        {
            $paramserver = New-Object Microsoft.SqlServer.Management.Smo.Server
            $paramserver.ConnectionContext.ApplicationName = "dbatools PowerShell module - dbatools.io"
            $paramserver.ConnectionContext.ConnectionString = $server.ConnectionContext.ConnectionString
            
            if ($SqlCredential.username -ne $null)
            {
                $username = ($SqlCredential.username).TrimStart("\")
                
                if ($username -like "*\*")
                {
                    $username = $username.Split("\")[1]
                    $authtype = "Windows Authentication with Credential"
                    $paramserver.ConnectionContext.LoginSecure = $true
                    $paramserver.ConnectionContext.ConnectAsUser = $true
                    $paramserver.ConnectionContext.ConnectAsUserName = $username
                    $paramserver.ConnectionContext.ConnectAsUserPassword = ($SqlCredential).GetNetworkCredential().Password
                }
                else
                {
                    $authtype = "SQL Authentication"
                    $paramserver.ConnectionContext.LoginSecure = $false
                    $paramserver.ConnectionContext.set_Login($username)
                    $paramserver.ConnectionContext.set_SecurePassword($SqlCredential.Password)
                }
            }
            
            $paramserver.ConnectionContext.Connect()
            return $paramserver
        }
        
        if ($server.ConnectionContext.IsOpen -eq $false)
        {
            $server.ConnectionContext.Connect()
        }
        
        # Update cache for instance names
        if ([Sqlcollective.Dbatools.TabExpansion.TabExpansionHost]::Cache["sqlinstance"] -notcontains $ConvertedSqlInstance.FullSmoName.ToLower())
        {
            [Sqlcollective.Dbatools.TabExpansion.TabExpansionHost]::Cache["sqlinstance"] += $ConvertedSqlInstance.FullSmoName.ToLower()
        }
        
        # Update cache for database names
        [Sqlcollective.Dbatools.TabExpansion.TabExpansionHost]::Cache["database"][$ConvertedSqlInstance.FullSmoName.ToLower()] = $server.Databases.Name
        
        return $server
    }
    #endregion Input Object was a server object
    
    #region Input Object was anything else
    # This seems a little complex but is required because some connections do TCP,SqlInstance
    $server = New-Object Microsoft.SqlServer.Management.Smo.Server $ConvertedSqlInstance.FullSmoName
    $server.ConnectionContext.ApplicationName = "dbatools PowerShell module - dbatools.io"
    
	<#
	 Just realized this will not work because it's SMO ;) We will return to if this is still needed and how to handle it in 1.0.
	
	if ($server.Configuration.SmoAndDmoXPsEnabled.RunValue -eq 0)
    {
        Write-Error "Accessing this server via SQL Management Objects (SMO) or Distributed Management Objects (DMO) is currently not permitted.
                     Enable the option 'SMO and DMO XPs' on your instance using sp_configure to continue.
                     Note that this will require 'Show Advanced Options' to be enabled using sp_configure as well."
        break
    }
	#>
    
    try
    {
        if ($SqlCredential.username -ne $null)
        {
            $username = ($SqlCredential.username).TrimStart("\")
            
            if ($username -like "*\*")
            {
                $username = $username.Split("\")[1]
                $authtype = "Windows Authentication with Credential"
                $server.ConnectionContext.LoginSecure = $true
                $server.ConnectionContext.ConnectAsUser = $true
                $server.ConnectionContext.ConnectAsUserName = $username
                $server.ConnectionContext.ConnectAsUserPassword = ($SqlCredential).GetNetworkCredential().Password
            }
            else
            {
                $authtype = "SQL Authentication"
                $server.ConnectionContext.LoginSecure = $false
                $server.ConnectionContext.set_Login($username)
                $server.ConnectionContext.set_SecurePassword($SqlCredential.Password)
            }
        }
    }
    catch { }
    
    try
    {
        if ($ParameterConnection)
        {
            $server.ConnectionContext.ConnectTimeout = 7
        }
        
        $server.ConnectionContext.Connect()
    }
    catch
    {
        $message = $_.Exception.InnerException.InnerException
        $message = $message.ToString()
        $message = ($message -Split '-->')[0]
        $message = ($message -Split 'at System.Data.SqlClient')[0]
        $message = ($message -Split 'at System.Data.ProviderBase')[0]
        throw "Can't connect to $ConvertedSqlInstance`: $message "
    }
    
    if (-not $RegularUser)
    {
        if ($server.ConnectionContext.FixedServerRoles -notmatch "SysAdmin")
        {
            throw "Not a sysadmin on $ConvertedSqlInstance. Quitting."
        }
    }
    
    if (-not $ParameterConnection)
    {
        $server.SetDefaultInitFields([Microsoft.SqlServer.Management.Smo.Trigger], 'IsSystemObject')
        $server.SetDefaultInitFields([Microsoft.SqlServer.Management.Smo.Rule], 'IsSystemObject')
        $server.SetDefaultInitFields([Microsoft.SqlServer.Management.Smo.Schema], 'IsSystemObject')
        $server.SetDefaultInitFields([Microsoft.SqlServer.Management.Smo.SqlAssembly], 'IsSystemObject')
        $server.SetDefaultInitFields([Microsoft.SqlServer.Management.Smo.Table], 'IsSystemObject')
        $server.SetDefaultInitFields([Microsoft.SqlServer.Management.Smo.View], 'IsSystemObject')
        $server.SetDefaultInitFields([Microsoft.SqlServer.Management.Smo.StoredProcedure], 'IsSystemObject')
        $server.SetDefaultInitFields([Microsoft.SqlServer.Management.Smo.UserDefinedFunction], 'IsSystemObject')
        
        if ($server.VersionMajor -eq 8)
        {
            # 2000
            $server.SetDefaultInitFields([Microsoft.SqlServer.Management.Smo.Database], 'ReplicationOptions', 'Collation', 'CompatibilityLevel', 'CreateDate', 'ID', 'IsAccessible', 'IsFullTextEnabled', 'IsUpdateable', 'LastBackupDate', 'LastDifferentialBackupDate', 'LastLogBackupDate', 'Name', 'Owner', 'PrimaryFilePath', 'ReadOnly', 'RecoveryModel', 'Status', 'Version')
            $server.SetDefaultInitFields([Microsoft.SqlServer.Management.Smo.Login], 'CreateDate', 'DateLastModified', 'DefaultDatabase', 'DenyWindowsLogin', 'IsSystemObject', 'Language', 'LanguageAlias', 'LoginType', 'Name', 'Sid', 'WindowsLoginAccessType')
        }
        
        
        elseif ($server.VersionMajor -eq 9 -or $server.VersionMajor -eq 10)
        {
            # 2005 and 2008
            $server.SetDefaultInitFields([Microsoft.SqlServer.Management.Smo.Database], 'ReplicationOptions', 'BrokerEnabled', 'Collation', 'CompatibilityLevel', 'CreateDate', 'ID', 'IsAccessible', 'IsFullTextEnabled', 'IsMirroringEnabled', 'IsUpdateable', 'LastBackupDate', 'LastDifferentialBackupDate', 'LastLogBackupDate', 'Name', 'Owner', 'PrimaryFilePath', 'ReadOnly', 'RecoveryModel', 'Status', 'Trustworthy', 'Version')
            $server.SetDefaultInitFields([Microsoft.SqlServer.Management.Smo.Login], 'AsymmetricKey', 'Certificate', 'CreateDate', 'Credential', 'DateLastModified', 'DefaultDatabase', 'DenyWindowsLogin', 'ID', 'IsDisabled', 'IsLocked', 'IsPasswordExpired', 'IsSystemObject', 'Language', 'LanguageAlias', 'LoginType', 'MustChangePassword', 'Name', 'PasswordExpirationEnabled', 'PasswordPolicyEnforced', 'Sid', 'WindowsLoginAccessType')
        }
        
        else
        {
            # 2012 and above
            $server.SetDefaultInitFields([Microsoft.SqlServer.Management.Smo.Database], 'ReplicationOptions', 'ActiveConnections', 'AvailabilityDatabaseSynchronizationState', 'AvailabilityGroupName', 'BrokerEnabled', 'Collation', 'CompatibilityLevel', 'ContainmentType', 'CreateDate', 'ID', 'IsAccessible', 'IsFullTextEnabled', 'IsMirroringEnabled', 'IsUpdateable', 'LastBackupDate', 'LastDifferentialBackupDate', 'LastLogBackupDate', 'Name', 'Owner', 'PrimaryFilePath', 'ReadOnly', 'RecoveryModel', 'Status', 'Trustworthy', 'Version')
            $server.SetDefaultInitFields([Microsoft.SqlServer.Management.Smo.Login], 'AsymmetricKey', 'Certificate', 'CreateDate', 'Credential', 'DateLastModified', 'DefaultDatabase', 'DenyWindowsLogin', 'ID', 'IsDisabled', 'IsLocked', 'IsPasswordExpired', 'IsSystemObject', 'Language', 'LanguageAlias', 'LoginType', 'MustChangePassword', 'Name', 'PasswordExpirationEnabled', 'PasswordHashAlgorithm', 'PasswordPolicyEnforced', 'Sid', 'WindowsLoginAccessType')
        }
    }
    
    # Update cache for instance names
    if ([Sqlcollective.Dbatools.TabExpansion.TabExpansionHost]::Cache["sqlinstance"] -notcontains $ConvertedSqlInstance.FullSmoName.ToLower())
    {
        [Sqlcollective.Dbatools.TabExpansion.TabExpansionHost]::Cache["sqlinstance"] += $ConvertedSqlInstance.FullSmoName.ToLower()
    }
    
    # Update cache for database names
    [Sqlcollective.Dbatools.TabExpansion.TabExpansionHost]::Cache["database"][$ConvertedSqlInstance.FullSmoName.ToLower()] = $server.Databases.Name
    
    return $server
    #endregion Input Object was anything else
}