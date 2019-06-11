function Add-DbaRegServer {
    <#
    .SYNOPSIS
        Adds registered servers to SQL Server Central Management Server (CMS)

    .DESCRIPTION
        Adds registered servers to SQL Server Central Management Server (CMS). If you need more flexiblity, look into Import-DbaRegServer which
        accepts multiple kinds of input and allows you to add reg servers from different CMSes.

    .PARAMETER SqlInstance
        The target SQL Server instance

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Windows and SQL Authentication supported. Accepts credential objects (Get-Credential)

    .PARAMETER ServerName
        Server Name is the actual SQL instance name (labeled Server Name)

    .PARAMETER Name
        Name is basically the nickname in SSMS CMS interface (labeled Registered Server Name)

    .PARAMETER Description
        Adds a description for the registered server

    .PARAMETER Group
        Adds the registered server to a specific group.

    .PARAMETER ActiveDirectoryTenant
	Active Directory Tenant

    .PARAMETER ActiveDirectoryUserId
        Active Directory User id

    .PARAMETER AuthenticationType
        Authentication type for connections where the connection string isn't sufficient to discover it

    .PARAMETER ConnectionString
        SQL Server connection string

    .PARAMETER OtherParams
        Additional parameters to append to the connection string

    .PARAMETER ServerObject
        SMO Objects

    .PARAMETER InputObject
        Allows the piping of a registered server group

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER Confirm
        Prompts you for confirmation before executing any changing operations within the command.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.

        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.

        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: RegisteredServer, CMS
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Add-DbaRegServer

    .EXAMPLE
        PS C:\> Add-DbaRegServer -SqlInstance sql2008 -ServerName sql01

        Creates a registered server on sql2008's CMS which points to the SQL Server, sql01. When scrolling in CMS, the name "sql01" will be visible.

    .EXAMPLE
        PS C:\> Add-DbaRegServer -SqlInstance sql2008 -ServerName sql01 -Name "The 2008 Clustered Instance" -Description "HR's Dedicated SharePoint instance"

        Creates a registered server on sql2008's CMS which points to the SQL Server, sql01. When scrolling in CMS, "The 2008 Clustered Instance" will be visible.
        Clearly this is hard to explain ;)

    .EXAMPLE
        PS C:\> Add-DbaRegServer -SqlInstance sql2008 -ServerName sql01 -Group hr\Seattle

        Creates a registered server on sql2008's CMS which points to the SQL Server, sql01. When scrolling in CMS, the name "sql01" will be visible within the Seattle group which is in the hr group.

    .EXAMPLE
        PS C:\> Get-DbaRegServerGroup -SqlInstance sql2008 -Group hr\Seattle | Add-DbaRegServer -ServerName sql01111

        Creates a registered server on sql2008's CMS which points to the SQL Server, sql01. When scrolling in CMS, the name "sql01" will be visible within the Seattle group which is in the hr group.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string]$ServerName,
        [string]$Name = $ServerName,
        [string]$Description,
        [object]$Group,
        [ValidateSet('Windows Authentication', 'SQL Server Authentication', 'AD Universal with MFA Support', 'AD - Password', 'AD - Integrated')]
        [string]$AuthenticationType,
        [string]$ActiveDirectoryTenant,
        [string]$ActiveDirectoryUserId,
        [string]$ConnectionString,
        [string]$OtherParams,
        [parameter(ValueFromPipeline)]
        [Microsoft.SqlServer.Management.RegisteredServers.ServerGroup[]]$InputObject,
        [parameter(ValueFromPipeline)]
        [Microsoft.SqlServer.Management.Smo.Server[]]$ServerObject,
        [switch]$EnableException
    )
    begin {
        $authtype = switch ($AuthenticationType) {
            "Windows Authentication" { 3 }
            "SQL Server Authentication" {  }
            "AD Universal with MFA Support" {  }
            "AD - Password" { 2 }
            "AD - Integrated" { 3 }
        }
    }
    process {
        # double check in case a null name was bound
        if (-not $PSBoundParameters.ServerName -and -not $PSBoundParameters.ServerObject) {
            Stop-Function -Message "You must specify either ServerName or ServerObject"
            return
        }
        if (-not $Name) {
            $Name = $ServerName
        }

        if (-not $SqlInstance -and -not $InputObject) {
            Write-Message -Level Verbose -Message "Parsing local"
            if (($Group)) {
                if ($Group -is [Microsoft.SqlServer.Management.RegisteredServers.ServerGroup]) {
                    $InputObject += Get-DbaRegServerGroup -Group $Group.Name
                } else {
                    Write-Message -Level Verbose -Message "String group provided"
                    $InputObject += Get-DbaRegServerGroup -Group $Group
                }
            } else {
                Write-Message -Level Verbose -Message "No group passed, getting root"
                $InputObject += Get-DbaRegServerGroup -Id 1
            }
        }

        foreach ($instance in $SqlInstance) {
            if (($Group)) {
                if ($Group -is [Microsoft.SqlServer.Management.RegisteredServers.ServerGroup]) {
                    $InputObject += Get-DbaRegServerGroup -SqlInstance $instance -SqlCredential $SqlCredential -Group $Group.Name
                } else {
                    $InputObject += Get-DbaRegServerGroup -SqlInstance $instance -SqlCredential $SqlCredential -Group $Group
                }
            } else {
                $InputObject += Get-DbaRegServerGroup -SqlInstance $instance -SqlCredential $SqlCredential -Id 1
            }

            if (-not $InputObject) {
                Stop-Function -Message "No matching groups found on $instance" -Continue
            }
        }

        foreach ($reggroup in $InputObject) {
            if ($reggroup.Source -eq "Azure Data Studio") {
                Stop-Function -Message "You cannot use dbatools to remove or add registered servers in Azure Data Studio" -Continue
            }
            if ($SqlInstance) {
                $target = $reggroup.ParentServer.SqlInstance
            } else {
                $target = "Local Registered Servers"
            }
            if ($Pscmdlet.ShouldProcess($target, "Adding $ServerName")) {

                if ($ServerObject) {
                    foreach ($server in $ServerObject) {
                        if (-not $PSBoundParameters.Name) {
                            $Name = $server.Name
                        }
                        if (-not $PSBoundParameters.ServerName) {
                            $ServerName = $server.Name
                        }
                        try {
                            $newserver = New-Object Microsoft.SqlServer.Management.RegisteredServers.RegisteredServer($reggroup, $Name)
                            $newserver.ServerName = $ServerName
                            $newserver.Description = $Description
                            $newserver.ConnectionString = $server.ConnectionContext.ConnectionString
                            $newserver.SecureConnectionString = $server.ConnectionContext.SecureConnectionString
                            $newserver.ActiveDirectoryTenant = $ActiveDirectoryTenant
                            $newserver.ActiveDirectoryUserId = $ActiveDirectoryUserId
                            $newserver.OtherParams = $OtherParams
                            $newserver.CredentialPersistenceType = "PersistLoginNameAndPassword"
                            $newserver.Create()

                            Get-DbaRegServer -SqlInstance $reggroup.ParentServer -Name $Name -ServerName $ServerName
                        } catch {
                            Stop-Function -Message "Failed to add $ServerName on $target" -ErrorRecord $_ -Continue
                        }
                    }
                } else {
                    try {
                        $newserver = New-Object Microsoft.SqlServer.Management.RegisteredServers.RegisteredServer($reggroup, $Name)
                        $newserver.ServerName = $ServerName
                        $newserver.Description = $Description
                        $newserver.ConnectionString = $ConnectionString
                        $newserver.ActiveDirectoryTenant = $ActiveDirectoryTenant
                        $newserver.ActiveDirectoryUserId = $ActiveDirectoryUserId
                        $newserver.OtherParams = $OtherParams
                        $newserver.Create()

                        Get-DbaRegServer -SqlInstance $reggroup.ParentServer -Name $Name -ServerName $ServerName
                    } catch {
                        Stop-Function -Message "Failed to add $ServerName on $target" -ErrorRecord $_ -Continue
                    }
                }
            }
        }
    }
}