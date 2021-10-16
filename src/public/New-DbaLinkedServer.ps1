function New-DbaLinkedServer {
    <#
    .SYNOPSIS
        Creates a new linked server.

    .DESCRIPTION
        Creates a new linked server. See the Microsoft documentation for sp_addlinkedserver for more details on the parameters.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. This can be a collection and receive pipeline input to allow the function
        to be executed against multiple SQL Server instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER LinkedServer
        The name of the linked server.

    .PARAMETER ServerProduct
        The product name of the data source.

    .PARAMETER Provider
        The unique ID of the provider.

    .PARAMETER DataSource
        The name of the data source.

    .PARAMETER Location
        The location of the database.

    .PARAMETER ProviderString
        The provider connection string.

    .PARAMETER Catalog
        The catalog or default database.

    .PARAMETER InputObject
        Allows piping from Connect-DbaInstance.

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER Confirm
        Prompts you for confirmation before executing any changing operations within the command.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Security, Server
        Author: Adam Lancaster https://github.com/lancasteradam

        dbatools PowerShell module (https://dbatools.io)
        Copyright: (c) 2021 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/New-DbaLinkedServer

    .EXAMPLE
        PS C:\>New-DbaLinkedServer -SqlInstance sql01 -LinkedServer linkedServer1 -ServerProduct mssql -Provider sqlncli -DataSource sql02

        Creates a new linked server named linkedServer1 on the sql01 instance. The link is via the SQL Native Client and is connected to the sql02 instance.

    .EXAMPLE
        PS C:\>Connect-DbaInstance -SqlInstance sql01 | New-DbaLinkedServer -LinkedServer linkedServer1 -ServerProduct mssql -Provider sqlncli -DataSource sql02

        Creates a new linked server named linkedServer1 on the sql01 instance. The link is via the SQL Native Client and is connected to the sql02 instance. The sql01 instance is passed in via pipeline.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Low')]
    param (
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string]$LinkedServer,
        [string]$ServerProduct,
        [string]$Provider,
        [string]$DataSource,
        [string]$Location,
        [string]$ProviderString,
        [string]$Catalog,
        [parameter(ValueFromPipeline)]
        [Microsoft.SqlServer.Management.Smo.Server[]]$InputObject,
        [switch]$EnableException
    )
    process {

        if (Test-Bound -Not -ParameterName LinkedServer) {
            Stop-Function -Message "LinkedServer is required"
            return
        }

        foreach ($instance in $SqlInstance) {
            $InputObject += Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
        }

        foreach ($server in $InputObject) {

            if ($server.LinkedServers.Name -contains $LinkedServer) {
                Stop-Function -Message "Linked server $LinkedServer already exists on $($server.Name)" -Continue
            }

            if ($Pscmdlet.ShouldProcess($server.Name, "Creating the linked server $LinkedServer on $($server.Name)")) {
                try {
                    $newLinkedServer = New-Object Microsoft.SqlServer.Management.Smo.LinkedServer -ArgumentList $server, $LinkedServer

                    if (Test-Bound ServerProduct) {
                        $newLinkedServer.ProductName = $ServerProduct
                    }

                    if (Test-Bound Provider) {
                        $newLinkedServer.ProviderName = $Provider
                    }

                    if (Test-Bound DataSource) {
                        $newLinkedServer.DataSource = $DataSource
                    }

                    if (Test-Bound Location) {
                        $newLinkedServer.Location = $Location
                    }

                    if (Test-Bound ProviderString) {
                        $newLinkedServer.ProviderString = $ProviderString
                    }

                    if (Test-Bound Catalog) {
                        $newLinkedServer.Catalog = $Catalog
                    }

                    $newLinkedServer.Create()

                    $server | Get-DbaLinkedServer -LinkedServer $LinkedServer
                } catch {
                    Stop-Function -Message "Failure on $($server.Name) to create the linked server $LinkedServer" -ErrorRecord $_ -Continue
                }
            }
        }
    }
}