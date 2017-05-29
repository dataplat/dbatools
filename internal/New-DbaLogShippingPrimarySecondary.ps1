function New-DbaLogShippingPrimarySecondary
{
<#
.SYNOPSIS 
New-DbaLogShippingPrimarySecondary adds an entry for a secondary database.

.DESCRIPTION
New-DbaLogShippingPrimarySecondary adds an entry for a secondary database.
This is executed on the primary server.

.PARAMETER SqlInstance
SQL Server instance. You must have sysadmin access and server version must be SQL Server version 2000 or greater.

.PARAMETER SqlCredential
Allows you to login to servers using SQL Logins as opposed to Windows Auth/Integrated/Trusted. To use:
$scred = Get-Credential, then pass $scred object to the -SqlCredential parameter. 
To connect as a different Windows user, run PowerShell as that user.

.PARAMETER PrimaryDatabase
Is the name of the database on the primary server. 

.PARAMETER SecondaryDatabase
Is the name of the secondary database.

.PARAMETER SecondaryServer
Is the name of the secondary server.

.PARAMETER SecondarySqlCredential
Allows you to login to servers using SQL Logins as opposed to Windows Auth/Integrated/Trusted. To use:
$scred = Get-Credential, then pass $scred object to the -SecondarySqlCredential parameter. 

.PARAMETER WhatIf
Shows what would happen if the command were to run. No actions are actually performed.

.PARAMETER Confirm
Prompts you for confirmation before executing any changing operations within the command.

.PARAMETER Silent
Use this switch to disable any kind of verbose messages

.NOTES 
Original Author: Sander Stad (@sqlstad, sqlstad.nl)
Tags: Log shipping, primary database, secondary database
	
Website: https://dbatools.io
Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

.LINK
https://dbatools.io/New-DbaLogShippingPrimarySecondary

.EXAMPLE   
New-DbaLogShippingPrimarySecondary -SqlInstance sql1 -PrimaryDatabase DB1 -SecondaryServer sql2 -SecondaryDatabase DB1_DR


#>

    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = "Low")]
	
	param (
		[parameter(Mandatory = $true)]
		[Alias("ServerInstance", "SqlServer")]
		[object]$SqlInstance,

        [Parameter(Mandatory = $false)]
        [System.Management.Automation.PSCredential]
        $SqlCredential,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$PrimaryDatabase,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$SecondaryDatabase,
        
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [object]$SecondaryServer,

        [Parameter(Mandatory = $false)]
        [System.Management.Automation.PSCredential]
        $SecondarySqlCredential,

        [switch]$Silent
    )

    # Try connecting to the instance
    Write-Message -Message "Attempting to connect to $SqlInstance" -Level Verbose
    try {
        $ServerPrimary = Connect-SqlServer -SqlServer $SqlInstance -SqlCredential $SqlCredential
    }
    catch {
        Stop-Function -Message "Could not connect to Sql Server instance" -Target $SqlInstance -Continue
    }

    # Try connecting to the instance
    Write-Message -Message "Attempting to connect to $SecondaryServer" -Level Verbose
    try {
        $ServerSecondary = Connect-SqlServer -SqlServer $SecondaryServer -SqlCredential $SecondarySqlCredential
    }
    catch {
        Stop-Function -Message "Could not connect to Sql Server instance" -Target $SecondaryServer -Continue
    }

    # Check if the database is present on the source sql server
    if ($ServerPrimary.Databases.Name -notcontains $PrimaryDatabase) {
        Stop-Function -Message "Database $PrimaryDatabase is not available on instance $SqlInstance" -InnerErrorRecord $_ -Target $SqlInstance -Continue
    }

    # Check if the database is present on the destination sql server
    if ($ServerSecondary.Databases.Name -notcontains $SecondaryDatabase) {
        Stop-Function -Message "Database $SecondaryDatabase is not available on instance $SecondaryServer" -InnerErrorRecord $_ -Target $SecondaryServer -Continue
    }
    
    $Query = "SELECT primary_database FROM msdb.dbo.log_shipping_primary_databases WHERE primary_database = '$PrimaryDatabase'"

    try{
        $Result = Invoke-SqlCmd2 -ServerInstance $SqlInstance -Credential $SqlCredential -Database 'master' -Query $Query -ErrorAction SilentlyContinue
        if($Result.Count -eq 0 -or $Result[0] -ne $PrimaryDatabase){
            Stop-Function -Message "Database $PrimaryDatabase does not exist as log shipping primary.`nPlease run New-DbaLogShippingPrimaryDatabase first."  -InnerErrorRecord $_ -Target $SqlInstance -Continue
        }
    }
    catch{
        Stop-Function -Message "Error executing the query.`n$($_.Exception.Message)`n$Query" -InnerErrorRecord $_ -Target $SqlInstance -Continue
    }

    # Set the query for the log shipping primary and secondary
    $Query = "EXEC master.dbo.sp_add_log_shipping_primary_secondary 
        @primary_database = N'$PrimaryDatabase' 
        ,@secondary_server = N'$SecondaryServer' 
        ,@secondary_database = N'$SecondaryDatabase' 
        ,@overwrite = 1;"
    
    # Execute the query to add the log shipping primary
    if($PSCmdlet.ShouldProcess($SqlInstance, ("Configuring logshipping connecting the primary database $PrimaryDatabase to secondary database $SecondaryDatabase on $SqlInstance"))) 
    {
        try
        {
            Write-Message -Message "Configuring logshipping connecting the primary database $PrimaryDatabase to secondary database $SecondaryDatabase on $SqlInstance." -Level Output
            Invoke-SqlCmd2 -ServerInstance $SqlInstance -Credential $SqlCredential -Database 'master' -Query $Query
        }
        catch
        {
            Stop-Function -Message "Error executing the query.`n$($_.Exception.Message)`n$Query" -InnerErrorRecord $_ -Target $SqlInstance -Continue
        }
    }

    Write-Message -Message "Finished configuring of primary database $PrimaryDatabase to secondary database $SecondaryDatabase." -Level Output 
    
}