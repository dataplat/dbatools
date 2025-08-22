function Set-DbaMaxMemory {
    <#
    .SYNOPSIS
        Configures SQL Server 'Max Server Memory' setting using calculated recommendations or explicit values

    .DESCRIPTION
        Modifies the SQL Server 'Max Server Memory' configuration to prevent SQL Server from consuming all available system memory.
        This setting controls how much memory SQL Server can allocate for its buffer pool and other memory consumers, leaving
        adequate memory for the operating system and other applications.

        When no explicit value is provided, the function calculates an optimal recommendation using a proven formula that reserves
        memory based on total system RAM. This formula accounts for operating system overhead, scales appropriately for servers
        with different memory configurations, and can handle multiple SQL Server instances on the same server.

        Inspired by Jonathan Kehayias's post about SQL Server Max memory (http://bit.ly/sqlmemcalc), this uses a formula to
        determine the default optimum RAM to use, then sets the SQL max value to that number.

        Jonathan notes that the formula used provides a *general recommendation* that doesn't account for everything that may
        be going on in your specific environment.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Max
        Specifies the max megabytes (MB)

    .PARAMETER InputObject
        A InputObject returned by Test-DbaMaxMemory

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .PARAMETER WhatIf
        Shows what would happen if the cmdlet runs. The cmdlet is not run.

    .PARAMETER Confirm
        Prompts you for confirmation before running the cmdlet.

    .NOTES
        Tags: MaxMemory, Memory
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Set-DbaMaxMemory

    .EXAMPLE
        PS C:\> Set-DbaMaxMemory sqlserver1

        Set max memory to the recommended on just one server named "sqlserver1"

    .EXAMPLE
        PS C:\> Set-DbaMaxMemory -SqlInstance sqlserver1 -Max 2048

        Explicitly set max memory to 2048 on just one server, "sqlserver1"

    .EXAMPLE
        PS C:\> Get-DbaRegServer -SqlInstance sqlserver | Test-DbaMaxMemory | Where-Object { $_.MaxValue -gt $_.Total } | Set-DbaMaxMemory

        Find all servers in SQL Server Central Management Server that have Max SQL memory set to higher than the total memory
        of the server (think 2147483647), then pipe those to Set-DbaMaxMemory and use the default recommendation.

    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param (
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [int]$Max,
        [Parameter(ValueFromPipeline)]
        [PSCustomObject[]]$InputObject,
        [switch]$EnableException
    )
    begin {
        if ($Max -eq 0) {
            $UseRecommended = $true
        }
    }
    process {
        if ($SqlInstance) {
            $InputObject += Test-DbaMaxMemory -SqlInstance $SqlInstance -SqlCredential $SqlCredential
        }

        foreach ($result in $InputObject) {
            $server = $result.Server
            Add-Member -Force -InputObject $result -NotePropertyName PreviousMaxValue -NotePropertyValue $result.MaxValue

            try {
                if ($UseRecommended) {
                    Write-Message -Level Verbose -Message "Change $server SQL Server Max Memory from $($result.MaxValue) to $($result.RecommendedValue) "

                    if ($result.RecommendedValue -eq 0 -or $null -eq $result.RecommendedValue) {
                        $maxMem = $result.RecommendedValue
                        Write-Message -Level VeryVerbose -Message "Max memory recommended: $maxMem"
                        $server.Configuration.MaxServerMemory.ConfigValue = $maxMem
                    } else {
                        $server.Configuration.MaxServerMemory.ConfigValue = $result.RecommendedValue
                    }
                } else {
                    Write-Message -Level Verbose -Message "Change $server SQL Server Max Memory from $($result.MaxValue) to $Max "
                    $server.Configuration.MaxServerMemory.ConfigValue = $Max
                }

                if ($PSCmdlet.ShouldProcess($server.Name, "Change Max Memory from $($result.PreviousMaxValue) to $($server.Configuration.MaxServerMemory.ConfigValue)")) {
                    try {
                        $server.Configuration.Alter()
                        $result.MaxValue = $server.Configuration.MaxServerMemory.ConfigValue
                    } catch {
                        Stop-Function -Message "Failed to apply configuration change for $server" -ErrorRecord $_ -Target $server -Continue
                    }

                    Add-Member -InputObject $result -Force -MemberType NoteProperty -Name MaxValue -Value $result.MaxValue
                    Select-DefaultView -InputObject $result -Property ComputerName, InstanceName, SqlInstance, Total, MaxValue, PreviousMaxValue
                }
            } catch {
                Stop-Function -Message "Could not modify Max Server Memory for $server" -ErrorRecord $_ -Target $server -Continue
            }
        }
    }
}