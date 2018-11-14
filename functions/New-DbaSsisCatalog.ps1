function New-DbaSsisCatalog {
    <#
    .SYNOPSIS
        Enables the SSIS Catalog on a SQL Server 2012+

    .DESCRIPTION
        After installing the SQL Server Engine and SSIS you still have to enable the SSIS Catalog. This function will enable the catalog and gives the option of supplying the password.

    .PARAMETER SqlInstance
        SQL Server you wish to run the function on.

    .PARAMETER SqlCredential
        Credentials used to connect to the SQL Server

    .PARAMETER Password
        Required password that will be used for the security key in SSISDB.

    .PARAMETER SsisCatalog
        SSIS catalog name. By default, this is SSISDB.

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER Confirm
        Prompts you for confirmation before executing any changing operations within the command.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: SSIS, SSISDB, Catalog
        Author: Stephen Bennett, https://sqlnotesfromtheunderground.wordpress.com/

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/New-DbaSsisCatalog

    .EXAMPLE
        PS C:\> $password = ConvertTo-SecureString MyVisiblePassWord -AsPlainText -Force
        PS C:\> New-DbaSsisCatalog -SqlInstance sql2016 -Password $password

        Creates the SSIS Catalog on server DEV01 with the specified password.

    .EXAMPLE
        PS C:\> $password = Read-Host -AsSecureString -Prompt "Enter password"
        PS C:\> New-DbaSsisCatalog -SqlInstance DEV01 -Password $password

        Creates the SSIS Catalog on server DEV01 with the specified password.

    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [Alias("ServerInstance", "SqlServer")]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [parameter(Mandatory)]
        [Security.SecureString]$Password,
        [string]$SsisCatalog = "SSISDB",
        [Alias('Silent')]
        [switch]$EnableException
    )

    process {
        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 10
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            ## check if SSIS and Engine running on box
            $services = Get-DbaService -ComputerName $server.ComputerName

            $ssisservice = $Services | Where-Object { $_.ServiceType -eq "SSIS" -and $_.State -eq "Running" }

            if (-not $ssisservice) {
                Stop-Function -Message "SSIS is not running on $instance" -Continue -Target $instance
            }

            #if SQL 2012 or higher only validate databases with ContainmentType = NONE
            $clrenabled = Get-DbaSpConfigure -SqlInstance $server -Config IsSqlClrEnabled

            if (!$clrenabled.RunningValue) {
                Stop-Function -Message 'CLR Integration must be enabled.  You can enable it by running Set-DbaSpConfigure -SqlInstance sql2012 -Config IsSqlClrEnabled -Value $true' -Continue -Target $instance
            }

            try {
                $ssis = New-Object Microsoft.SqlServer.Management.IntegrationServices.IntegrationServices $server
            } catch {
                Stop-Function -Message "Can't load server" -Target $instance -ErrorRecord $_
                return
            }

            if ($ssis.Catalogs[$SsisCatalog]) {
                Stop-Function -Message "SSIS Catalog already exists" -Continue -Target $ssis.Catalogs[$SsisCatalog]
            } else {
                if ($Pscmdlet.ShouldProcess($server, "Creating SSIS catalog: $SsisCatalog")) {
                    try {
                        $ssisdb = New-Object Microsoft.SqlServer.Management.IntegrationServices.Catalog ($ssis, $SsisCatalog, $(([System.Runtime.InteropServices.marshal]::PtrToStringAuto([System.Runtime.InteropServices.marshal]::SecureStringToBSTR($password)))))
                        $ssisdb.Create()

                        [pscustomobject]@{
                            ComputerName = $server.ComputerName
                            InstanceName = $server.ServiceName
                            SqlInstance  = $server.DomainInstanceName
                            SsisCatalog  = $SsisCatalog
                            Created      = $true
                        }
                    } catch {
                        Stop-Function -Message "Failed to create SSIS Catalog: $_" -Target $_ -Continue
                    }
                }
            }
        }
    }
}