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
Author: Stephen Bennett, https://sqlnotesfromtheunderground.wordpress.com/
Tags:
dbatools PowerShell module (https://dbatools.io, clemaire@gmail.com)
Copyright (C) 2016 Chrissy LeMaire
License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

.LINK
https://dbatools.io/New-DbaSsisCatalog

.EXAMPLE
$password = ConvertTo-SecureString MyVisiblePassWord -AsPlainText -Force
New-DbaSsisCatalog -SqlInstance sql2016 -Password $password

Creates the SSIS Catalog on server DEV01 with the specified password.

.EXAMPLE
$password = Read-Host -AsSecureString -Prompt "Enter password"
New-DbaSsisCatalog -SqlInstance DEV01 -Password $password

Creates the SSIS Catalog on server DEV01 with the specified password.

#>
    [CmdletBinding(SupportsShouldProcess = $true)]
    Param (
        [parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [Alias("ServerInstance", "SqlServer")]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [parameter(Mandatory = $true)]
        [Security.SecureString]$Password,
        [string]$SsisCatalog = "SSISDB",
        [switch][Alias('Silent')]$EnableException
    )

    process {
        foreach ($instance in $SqlInstance) {
            Write-Message -Level Verbose -Message "Attempting to connect to $instance"

            try {
                Write-Message -Level Verbose -Message "Connecting to $instance"
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $sqlcredential -MinimumVersion 10
            }
            catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            ## check if SSIS and Engine running on box
            $services = Get-DbaSqlService -ComputerName $server.NetName

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
            }
            catch {
                Stop-Function -Message "Can't load server" -Target $instance -ErrorRecord $_
                return
            }

            if ($ssis.Catalogs[$SsisCatalog]) {
                Stop-Function -Message "SSIS Catalog already exists" -Continue -Target $ssis.Catalogs[$SsisCatalog]
            }
            else {
                if ($Pscmdlet.ShouldProcess($server, "Creating SSIS catalog: $SsisCatalog")) {
                    try {
                        $ssisdb = New-Object Microsoft.SqlServer.Management.IntegrationServices.Catalog ($ssis, $SsisCatalog, $(([System.Runtime.InteropServices.marshal]::PtrToStringAuto([System.Runtime.InteropServices.marshal]::SecureStringToBSTR($password)))))
                        $ssisdb.Create()

                        [pscustomobject]@{
                            ComputerName = $server.NetName
                            InstanceName = $server.ServiceName
                            SqlInstance  = $server.DomainInstanceName
                            SsisCatalog  = $SsisCatalog
                            Created      = $true
                        }
                    }
                    catch {
                        Stop-Function -Message "Failed to create SSIS Catalog: $_" -Target $_ -Continue
                    }
                }
            }
        }
    }
}
