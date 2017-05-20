Function Remove-DbaMasterKey
{
<#
    .SYNOPSIS
        Deletes specified database master key
    
    .DESCRIPTION
        Deletes specified database master key.
    
    .PARAMETER SqlInstance
        The target SQL Server instance.
    
    .PARAMETER SqlCredential
        Allows you to login to SQL Server using alternative credentials.
    
    .PARAMETER Database
        The database where the master key will be removed.
    
    .PARAMETER All
        Purge the master keys from all databases on an instance.
    
    .PARAMETER Exclude
        List of databases to exclude from clearing all master keys
    
    .PARAMETER MasterKeyCollection
        Internal parameter to support pipeline input
    
    .PARAMETER Mode
        Controls how the function handles cases where it can't do anything due to missing database or key:
        Strict: Write a warning (default)
        Lazy:   Write a verbose message
        Report: Create a report object as part of the output
        The default action can be adjusted by using Set-DbaConfig to change the 'message.mode.default' configuration
    
    .PARAMETER Silent
        Use this switch to disable any kind of verbose messages
    
    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed.
    
    .PARAMETER Confirm
        Prompts you for confirmation before executing any changing operations within the command.
    
    .EXAMPLE
        Remove-DbaMasterKey -SqlInstance Server1
        
        The master key in the master database on server1 will be removed if it exists.
    
    .EXAMPLE
        Remove-DbaMasterKey -SqlInstance Server1 -Database db1 -Confirm:$false
        
        Supresses all prompts to remove the master key in the 'db1' database and drops the key.
    
    .EXAMPLE
        Remove-DbaMasterKey -SqlInstance Server1 -WhatIf
        
        Shows what would happen if the command were executed against server1
    
    .NOTES
        Tags: Certificate
        Website: https://dbatools.io
        Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
        License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0
#>
    [CmdletBinding(DefaultParameterSetName = "Default", SupportsShouldProcess = $true, ConfirmImpact = "High")]
    param (
        [parameter(Mandatory, ParameterSetName = "instanceExplicit")]
        [parameter(Mandatory, ParameterSetName = "instanceAll")]
        [Alias("ServerInstance", "SqlServer")]
        [DbaInstanceParameter[]]
        $SqlInstance,
        
        [System.Management.Automation.PSCredential]
        $SqlCredential,
        
        [parameter(Mandatory, ParameterSetName = "instanceExplicit")]
        [string[]]
        $Database,
        
        [parameter(Mandatory, ParameterSetName = "instanceAll")]
        [switch]
        $All,
        
        [parameter(ParameterSetName = "instanceAll")]
        [string[]]
        $Exclude,
        
        [parameter(ValueFromPipeline, ParameterSetName = "collection")]
        [Microsoft.SqlServer.Management.Smo.MasterKey[]]
        $MasterKeyCollection,
        
        [DbaMode]
        $Mode = (Get-DbaConfigValue -Name 'message.mode.default' -Fallback "Strict"),
        
        [switch]
        $Silent
    )
    
    begin
    {
        function Drop-Masterkey
        {
            [CmdletBinding()]
            Param (
                $masterkey,
                
                $mode = $Mode,
                
                $Silent = $Silent
            )
            $server = $masterkey.Parent.Parent
            $instance = $server.DomainInstanceName
            $cert = $masterkey.Name
            $db = $masterkey.Parent.Name
            
            if ($Pscmdlet.ShouldProcess($instance, "Dropping the master key for database '$db'"))
            {
                try
                {
                    $masterkey.Drop()
                    Write-Message -Level Verbose -Message "Successfully removed master key from the $db database on $instance"
                    
                    [pscustomobject]@{
                        ComputerName = $server.NetName
                        InstanceName = $server.ServiceName
                        SqlInstance = $server.DomainInstanceName
                        Database = $db.name
                        Status = "Success"
                    }
                }
                catch
                {
                    [pscustomobject]@{
                        ComputerName = $server.NetName
                        InstanceName = $server.ServiceName
                        SqlInstance = $server.DomainInstanceName
                        Database = $db.name
                        Status = "Failure"
                    }
                    Stop-Function -Message "Failed to drop master key from $db on $instance." -Target $db -InnerErrorRecord $_ -Continue
                }
            }
        }
    }
    process
    {
        foreach ($instance in $SqlInstance)
        {
            try
            {
                Write-Message -Level Verbose -Message "Connecting to $instance"
                $server = Connect-SqlServer -SqlServer $instance -SqlCredential $sqlcredential
            }
            catch
            {
                Stop-Function -Message "Failed to connect to: $instance" -Target $instance -InnerErrorRecord $_ -Continue
            }
            
            if ($All)
            {
                $Database = ($server.Databases | Where-Object Name -NotIn $Exclude).Name
            }
            
            :database foreach ($db in $Database)
            {
                $smodb = $server.Databases[$db]
                $masterkey = $smodb.MasterKey
                
                #region Case: Database Unknown
                if ($null -eq $smodb)
                {
                    switch ($Mode)
                    {
                        [DbaMode]::Strict { Stop-Function -Message "Database '$db' does not exist on $instance" -Target $smodb -Continue -ContinueLabel database }
                        [DbaMode]::Lazy
                        {
                            Write-Message -Level (Get-DbaConfigValue -Name 'message.mode.lazymessagelevel' -Fallback 4) -Message "Database '$db' does not exist on $instance" -Target $smodb
                            continue database
                        }
                        [DbaMode]::Report
                        {
                            [pscustomobject]@{
                                ComputerName = $server.NetName
                                InstanceName = $server.ServiceName
                                SqlInstance = $server.DomainInstanceName
                                Database = $db
                                Status = "Unknown Database"
                            }
                            continue database
                        }
                    }
                }
                #endregion Case: Database Unknown
                
                #region Case: No Master Key
                if ($null -eq $masterkey)
                {
                    switch ($Mode.ToString())
                    {
                        "Strict" { Stop-Function -Message "No master key exists in the $db database on $instance" -Target $smodb -Continue -ContinueLabel database }
                        "Lazy"
                        {
                            Write-Message -Level (Get-DbaConfigValue -Name 'message.mode.lazymessagelevel' -Fallback 4) -Message "No master key exists in the $db database on $instance" -Target $smodb
                            continue database
                        }
                        "Report"
                        {
                            [pscustomobject]@{
                                ComputerName = $server.NetName
                                InstanceName = $server.ServiceName
                                SqlInstance = $server.DomainInstanceName
                                Database = $db
                                Status = "No Masterkey"
                            }
                            continue database
                        }
                    }
                }
                #endregion Case: No Master Key
                
                Write-Message -Level Verbose -Message "Removing master key from $db"
                Drop-Masterkey -masterkey $masterkey
            }
        }
        
        foreach ($key in $MasterKeyCollection)
        {
            Write-Message -Level Verbose -Message "Removing master key: $key"
            Drop-Masterkey -masterkey $key
        }
    }
}



