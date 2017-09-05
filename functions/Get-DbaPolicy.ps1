Function Get-DbaPolicy
{
	<#
		.SYNOPSIS
			Returns polices from policy based management from an instance.
		.DESCRIPTION
			Returns details of policies with the option to filter on Category and SystemObjects.
			
		.PARAMETER SqlInstance
			SQL Server name or SMO object representing the SQL Server to connect to. This can be a collection and receive pipeline input to allow the function to be executed against multiple SQL Server instances.
		.PARAMETER SqlCredential
			SqlCredential object to connect as. If not specified, current Windows login will be used.
        .PARAMETER Category
        Filters results to only show policies in the category selected
        .PARAMETER SystemObject
        By default system objects are filtered out. Use this parameter to INCLUDE them 
		
		.NOTES
			Original Author: Chrissy LeMaire (@cl), netnerds.net
			Tags: PBM, PolicyBasedManagement
			
			Website: https://dbatools.io
			Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
			License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0
		.LINK
			https://dbatools.io/Get-DbaPolicy
        .EXAMPLE   
        Get-DbaPolicy -SqlInstance CMS
        Returns all policies from CMS server
        .EXAMPLE   
        Get-DbaPolicy -SqlInstance CMS $SqlCredential $cred
        Uses a credential $cred to connect and return all policies from CMS instance
        .EXAMPLE   
        Get-DbaPolicy -SqlInstance CMS -Category MorningCheck
        Returns all policies from CMS server that part of the PolicyCategory MorningCheck
	#>
	[CmdletBinding()]
	param (
		[parameter(Position = 0, Mandatory = $true, ValueFromPipeline = $True)]
		[Alias("ServerInstance", "SqlServer")]
		[DbaInstanceParameter[]]$SqlInstance,
		[Alias("Credential")]
		[PSCredential][System.Management.Automation.CredentialAttribute()]
		$SqlCredential,
        [string]$Category,
        [switch]$IncludeSystemObject
	)
	
    begin 
    {
    	try 
        { 
            $server = Connect-SqlServer -SqlServer $SqlServer -SqlCredential $SqlCredential 
        }
    	catch 
        { 
            write-output "failed to connect" 
        }
    	
    	$sqlconn = $server.ConnectionContext.SqlConnectionObject
    	$sqlStoreConnection = New-Object Microsoft.SqlServer.Management.Sdk.Sfc.SqlStoreConnection $sqlconn
        
        $filter
    
    }
    process
    {
    	# DMF is the Declarative Management Framework, Policy Based Management's old name
    	$store = New-Object Microsoft.SqlServer.Management.DMF.PolicyStore $sqlStoreConnection
    	
        if ($Category)
        {
            $store.Policies | Where {$_.PolicyCategory -eq $Category} | select Name, PolicyCategory, Condition, Enabled, HelpLink, HelpText, Description
        }
        else
        {
            if ($IncludeSystemObject)
            {
                $store.Policies | select Name, PolicyCategory, Condition, Enabled, HelpLink, HelpText, Description
            }    
            else
            {
                $store.Policies | Where-Object {$_.IsSystemObject -eq 0 } | select Name, PolicyCategory, Condition, Enabled, HelpLink, HelpText, Description
            }
        }
        
        $server.ConnectionContext.Disconnect()
    }
}

