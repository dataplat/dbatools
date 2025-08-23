function Test-DbaOptimizeForAdHoc {
    <#
    .SYNOPSIS
        Tests whether the SQL Server "optimize for ad-hoc workloads" configuration setting is enabled.

    .DESCRIPTION
        Checks the current value of the "optimize for ad-hoc workloads" server configuration option and compares it against the recommended setting of 1 (enabled). This setting helps prevent plan cache bloat by storing only compiled plan stubs for single-use ad hoc queries instead of full execution plans. DBAs typically enable this on servers with high volumes of ad hoc queries to reduce memory pressure and improve overall performance. Returns the current configuration value, recommended value, and guidance notes for each SQL Server instance.

        More info: https://msdn.microsoft.com/en-us/library/cc645587.aspx
        http://www.sqlservercentral.com/blogs/glennberry/2011/02/25/some-suggested-sql-server-2008-r2-instance-configuration-settings/

        These are just general recommendations for SQL Server and are a good starting point for setting the "optimize for ad-hoc workloads" option.

    .PARAMETER SqlInstance
        A collection of one or more SQL Server instance names to query.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Configure, SPConfigure
        Author: Brandon Abshire, netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Test-DbaOptimizeForAdHoc

    .EXAMPLE
        PS C:\> Test-DbaOptimizeForAdHoc -SqlInstance sql2008, sqlserver2012

        Validates whether Optimize for AdHoc Workloads setting is enabled for servers sql2008 and sqlserver2012.

    #>
    [CmdletBinding()]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstance[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [switch]$EnableException
    )

    begin {
        $notesAdHocZero = "Recommended configuration is 1 (enabled)."
        $notesAsRecommended = "Configuration is already set as recommended."
        $recommendedValue = 1
    }
    process {

        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 10
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            #Get current configured value
            $optimizeAdHoc = $server.Configuration.OptimizeAdhocWorkloads.ConfigValue

            #Setting notes for optimize adhoc value
            if ($optimizeAdHoc -eq $recommendedValue) {
                $notes = $notesAsRecommended
            } else {
                $notes = $notesAdHocZero
            }

            [PSCustomObject]@{
                ComputerName             = $server.ComputerName
                InstanceName             = $server.ServiceName
                SqlInstance              = $server.DomainInstanceName
                CurrentOptimizeAdHoc     = $optimizeAdHoc
                RecommendedOptimizeAdHoc = $recommendedValue
                Notes                    = $notes
            }
        }
    }
}