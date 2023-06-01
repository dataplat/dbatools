function Enable-DbaReplPublishing {
    <#
    .SYNOPSIS
        Enables replication publishing for the target SQL instances.

    .DESCRIPTION
        Enables replication publishing for the target SQL instances.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER SnapshotShare
         The share used to access snapshot files.

    .PARAMETER PublisherSqlLogin
        If this is used the PublisherSecurity will be set to use this.
        If not specified WindowsAuthentication can will used - this is the default, and recommended method.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .PARAMETER WhatIf
        If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

    .PARAMETER Confirm
        If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

    .NOTES
        Tags: Replication
        Author: Jess Pomfret (@jpomfret), jesspomfret.com

        Website: https://dbatools.io
        Copyright: (c) 2022 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Enable-DbaReplPublishing

    .EXAMPLE
        PS C:\> Enable-DbaReplPublishing -SqlInstance SqlBox1\Instance2 -StartupProcedure '[dbo].[StartUpProc1]'

        Attempts to set the procedure '[dbo].[StartUpProc1]' in the master database of SqlBox1\Instance2 for automatic execution when the instance is started.

    #>
    [CmdletBinding(DefaultParameterSetName = "Default", SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        $SnapshotShare = '/var/opt/mssql/ReplData', # TODO: default should handle linux\windows?
        [PSCredential]$PublisherSqlLogin,
        [switch]$EnableException
    )
    process {
        foreach ($instance in $SqlInstance) {
            try {
                $replServer = Get-DbaReplServer -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }
            Write-Message -Level Verbose -Message "Enabling replication publishing for $instance"

            try {
                if ($PSCmdlet.ShouldProcess($instance, "Enabling publishing on $instance")) {

                    if ($replServer.IsDistributor) {

                        $distPublisher = New-Object Microsoft.SqlServer.Replication.DistributionPublisher
                        $distPublisher.ConnectionContext = $replServer.ConnectionContext
                        $distPublisher.Name = $instance #- name of the Publisher.
                        $distPublisher.DistributionDatabase = $replServer.DistributionDatabases.Name #- the name of the database created in step 5.

                        #TODO: test snapshot path and warn\error?
                        #if (Test-DbaPath -SqlInstance mssql1 -Path $SnapshotShare) {
                        #    Stop-Function -Message ("Snapshot path '{0}' does not exist - will attempt to create it" -f $SnapshotShare) -ErrorRecord $_ -Target $instance -Continue
                        #}
                        $distPublisher.WorkingDirectory = $SnapshotShare

                        if ($PublisherSqlLogin) {
                            Write-Message -Level Verbose -Message "Configuring with a SQLLogin for PublisherSecurity"
                            $distPublisher.PublisherSecurity.WindowsAuthentication = $false
                            $distPublisher.PublisherSecurity.SqlStandardLogin = $PublisherSqlLogin.UserName
                            $distPublisher.PublisherSecurity.SecureSqlStandardPassword = $PublisherSqlLogin.Password

                        } else {
                            Write-Message -Level Verbose -Message "Configuring with WindowsAuth for PublisherSecurity"
                            $distPublisher.PublisherSecurity.WindowsAuthentication = $true  # TODO: test with windows auth
                        }

                        Write-Message -Level Debug -Message $distPublisher
                        # lots more properties to add as params
                        $distPublisher.Create()
                    } else {
                        Stop-Function -Message "$instance isn't currently enabled for distributing. Please enable that first." -ErrorRecord $_ -Target $instance -Continue
                    }
                }
            } catch {
                Stop-Function -Message "Unable to enable replication publishing" -ErrorRecord $_ -Target $instance -Continue
            }

            $replServer.Refresh()
            $replServer # TODO: Standard output

        }
    }
}



