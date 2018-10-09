#ValidationTags#Messaging,FlowControl,Pipeline,CodeStyle#
function Grant-DbaAgPermission {
<#
    .SYNOPSIS
        Grants endpoint and availability group permissions to a login.
        
    .DESCRIPTION
        Grants endpoint and availability group permissions to a login.
    
    .PARAMETER SqlInstance
        The target SQL Server instance or instances. This can be a collection and receive pipeline input to allow the function
        to be executed against multiple SQL Server instances.
        
    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Windows and SQL Authentication supported. Accepts credential objects (Get-Credential)
        
    .PARAMETER AvailabilityGroup
        Only modify specific availability groups.
   
    .PARAMETER Type
        Endpoint or availability group.
    
    .PARAMETER Permission
        Sets one or more permissions:
            Alter
            Connect
            Control
            CreateSequence
            Delete
            Execute
            Impersonate	
            Insert	
            Receive	
            References	
            Select	
            Send	
            TakeOwnership	
            Update	
            ViewChangeTracking	
            ViewDefinition	
        
        Connect is default.
    
    .PARAMETER InputObject
        Internal parameter to support piping from Get-DbaLogin.
        
    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed.
        
    .PARAMETER Confirm
        Prompts you for confirmation before executing any changing operations within the command.
    
    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.
        
    .NOTES
        Tags: AvailabilityGroup, HA, AG
        Author: Chrissy LeMaire (@cl), netnerds.net
        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT
        
    .LINK
        https://dbatools.io/Grant-DbaAgPermission
        
    .EXAMPLE
        PS C:\> Grant-DbaAgPermission -SqlInstance sqlserver2012 -AllAvailabilityGroup
        
        Adds all availability groups on the sqlserver2014 instance. Does not prompt for confirmation.
        
    .EXAMPLE
        PS C:\> Grant-DbaAgPermission -SqlInstance sqlserver2012 -AvailabilityGroup ag1, ag2 -Confirm
        
        Adds the ag1 and ag2 availability groups on sqlserver2012. Prompts for confirmation.
        
    .EXAMPLE
        PS C:\> Get-DbaDatabase -SqlInstance sqlserver2012 | Out-GridView -Passthru | Grant-DbaAgPermission -AvailabilityGroup ag1
        
        Adds selected databases from sqlserver2012 to ag1
  
    .EXAMPLE
        PS C:\> Get-DbaDbSharePoint -SqlInstance sqlcluster | Grant-DbaAgPermission -AvailabilityGroup SharePoint
        
        Adds SharePoint databases as found in SharePoint_Config on sqlcluster to ag1 on sqlcluster
    
    .EXAMPLE
        PS C:\> Get-DbaDbSharePoint -SqlInstance sqlcluster -ConfigDatabase SharePoint_Config_2019 | Grant-DbaAgPermission -AvailabilityGroup SharePoint
        
        Adds SharePoint databases as found in SharePoint_Config_2019 on sqlcluster to ag1 on sqlcluster
#>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Low')]
    param (
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string[]]$Login,
        [string[]]$AvailabilityGroup,
        [parameter(Mandatory)]
        [ValidateSet('Endpoint', 'AvailabilityGroup')]
        [string[]]$Type,
        [ValidateSet('Alter', 'Connect', 'Control', 'CreateSequence', 'Delete', 'Execute', 'Impersonate', 'Insert', 'Receive', 'References', 'Select', 'Send', 'TakeOwnership', 'Update', 'ViewChangeTracking', 'ViewDefinition')]
        [string[]]$Permission = "Connect",
        [parameter(ValueFromPipeline)]
        [Microsoft.SqlServer.Management.Smo.Login[]]$InputObject,
        [switch]$EnableException
    )
    process {
        if ($SqlInstance -and -not $Login) {
            Stop-Function -Message "You must specify one or more logins when using the SqlInstance parameter."
            return
        }
        
        if ($Type -contains "AvailabilityGroup" -and -not $AvailabilityGroup) {
            Stop-Function -Message "You must specify at least one availability group when using the AvailabilityGroup type."
            return
        }
        
        foreach ($instance in $SqlInstance) {
            $InputObject += Get-DbaLogin -SqlInstance $instance -SqlCredential $SqlCredential -Login $Login
            foreach ($account in $Login) {
                if ($account -notin $InputObject.Name) {
                    if ($account -match '\\') {
                        $InputObject += New-DbaLogin -SqlInstance $server -Login $account
                    }
                    else {
                        Stop-Function -Message "$account does not exist and cannot be created automatically" -Target $instance
                        return
                    }
                }
            }
        }
        
        foreach ($account in $InputObject) {
            $server = $account.Parent
            if ($Type -contains "Endpoint") {
                $endpoint = Get-DbaEndpoint -SqlInstance $server -Type DatabaseMirroring
                if (-not $endpoint) {
                    Stop-Function -Message "DatabaseMirroring endpoint does not exist on $server" -Target $server -Continue
                }
                
                foreach ($perm in $Permission) {
                    if ($Pscmdlet.ShouldProcess($server.Name, "Granting $perm on $endpoint")) {
                        $bigperms = New-Object Microsoft.SqlServer.Management.Smo.ObjectPermissionSet([Microsoft.SqlServer.Management.Smo.ObjectPermission]::$perm)
                        $endpoint.Grant($bigperms, $account.Name)
                    }
                }
            }
            
            if ($Type -contains "AvailabilityGroup") {
                $ags = Get-DbaAvailabilityGroup -SqlInstance $account.Parent -AvailabilityGroup $AvailabilityGroup
                foreach ($ag in $ags) {
                    foreach ($perm in $Permission) {
                        if ($perm -notin 'Alter', 'Control', 'TakeOwnership', 'ViewDefinition') {
                            Stop-Function -Message "$perm not supported by availability groups" -Continue
                        }
                        if ($Pscmdlet.ShouldProcess($server.Name, "Granting $perm on $ags")) {
                            $bigperms = New-Object Microsoft.SqlServer.Management.Smo.ObjectPermissionSet([Microsoft.SqlServer.Management.Smo.ObjectPermission]::$perm)
                            $ag.Grant($bigperms, $account.Name)
                        }
                    }
                }
            }
        }
    }
}