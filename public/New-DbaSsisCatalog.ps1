function New-DbaSsisCatalog {
    <#
    .SYNOPSIS
        Creates and enables the SSIS Catalog (SSISDB) database on SQL Server 2012+ instances

    .DESCRIPTION
        Creates the SSIS Catalog database (SSISDB) which is required before you can deploy, manage, or execute SSIS packages on the server. Installing SQL Server with SSIS doesn't automatically create this catalog - it's a separate post-installation step that requires CLR integration and a secure password for the master key. This function handles the entire setup process, including prerequisite validation, so you don't have to manually run SQL scripts or navigate through SQL Server Management Studio wizards.

    .PARAMETER SqlInstance
        SQL Server you wish to run the function on.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER SecurePassword
        Required password that will be used for the security key in SSISDB.

    .PARAMETER Credential
        Use a credential object instead of a securepassword

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
        PS C:\> $SecurePassword = Read-Host -AsSecureString -Prompt "Enter password"
        PS C:\> New-DbaSsisCatalog -SqlInstance DEV01 -SecurePassword $SecurePassword

        Creates the SSIS Catalog on server DEV01 with the specified password.

    .EXAMPLE
        PS C:\> New-DbaSsisCatalog -SqlInstance sql2016 -Credential usernamedoesntmatter

        Creates the SSIS Catalog on server DEV01 with the specified password in the credential prompt. As the example username suggets the username does not matter.
        This is simply an easier way to get a secure password.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [PSCredential]$Credential,
        [Alias("Password")]
        [Security.SecureString]$SecurePassword,
        [string]$SsisCatalog = "SSISDB",
        [switch]$EnableException
    )
    begin {
        if ($PSVersionTable.PSEdition -eq "Core") {
            Stop-Function -Message "This command is not supported on Linux or macOS"
            return
        }
        if (-not $SecurePassword -and -not $Credential) {
            Stop-Function -Message "You must specify either -SecurePassword or -Credential"
            return
        }
        if (-not $SecurePassword -and $Credential) {
            $SecurePassword = $Credential.Password
        }
    }
    process {
        if (Test-FunctionInterrupt) {
            return
        }
        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 10
            } catch {
                Stop-Function -Message "Error occurred while establishing connection to $instance" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            ## check if SSIS and Engine running on box
            try {
                $services = Get-DbaService -ComputerName $server.ComputerName -Credential $Credential -EnableException

                $ssisservice = $Services | Where-Object {
                    $_.ServiceType -eq "SSIS" -and $_.State -eq "Running"
                }
            } catch {
                Write-Message -Level Verbose "Could not connect using Get-DbaService ($PSItem). Trying Get-Service."
            }

            if (-not $ssisservice) {
                if ($instance.IsLocalhost) {
                    $services = Get-Service -ErrorAction Ignore
                } else {
                    $services = Invoke-Command2 -ComputerName $server.ComputerName -Credential $Credential -ScriptBlock { Get-Service } -ErrorAction Ignore
                }

                $ssisservice = $services | Where-Object {
                    ($_.ServiceType -eq "SSIS" -or $_.Name -match "MsDtsServer") -and $_.Status -eq "Running"
                }
                if (-not $ssisservice) {
                    Stop-Function -Message "SSIS is not running on $instance" -Continue -Target $instance
                }
            }

            #if SQL 2012 or higher only validate databases with ContainmentType = NONE
            $clrenabled = Get-DbaSpConfigure -SqlInstance $server -Name IsSqlClrEnabled

            if (-not $clrenabled.RunningValue) {
                Stop-Function -Message "CLR Integration must be enabled. You can enable it by running Set-DbaSpConfigure -SqlInstance $instance -Config IsSqlClrEnabled -Value `$true" -Continue -Target $instance
            }

            try {
                $ssis = New-Object Microsoft.SqlServer.Management.IntegrationServices.IntegrationServices $server
            } catch {
                Stop-Function -Message "Can't load server" -Target $instance -ErrorRecord $_
                return
            }

            if ($ssis.Catalogs.Count -gt 0) {
                Stop-Function -Message "SSIS Catalog already exists" -Continue -Target $ssis.Catalogs
            } else {
                if ($Pscmdlet.ShouldProcess($server, "Creating SSIS catalog: $SsisCatalog")) {
                    try {
                        $ssisdb = New-Object Microsoft.SqlServer.Management.IntegrationServices.Catalog ($ssis, $SsisCatalog, $(([System.Runtime.InteropServices.marshal]::PtrToStringAuto([System.Runtime.InteropServices.marshal]::SecureStringToBSTR($SecurePassword)))))
                    } catch {
                        Stop-Function -Message "Failed to create SSIS Catalog: $_" -Target $_ -Continue
                    }
                    try {
                        $ssisdb.Create()
                        [PSCustomObject]@{
                            ComputerName = $server.ComputerName
                            InstanceName = $server.ServiceName
                            SqlInstance  = $server.DomainInstanceName
                            SsisCatalog  = $SsisCatalog
                            Created      = $true
                        }
                    } catch {
                        $msg = $_.Exception.InnerException.InnerException.Message
                        if (-not $msg) {
                            $msg = $_
                        }
                        Stop-Function -Message "$msg" -Target $_ -Continue
                    }
                }
            }
        }
    }
}