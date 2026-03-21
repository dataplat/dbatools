function Test-DbaBuild {
    <#
    .SYNOPSIS
        Tests SQL Server build versions against patching compliance requirements

    .DESCRIPTION
        Evaluates SQL Server instances or build versions against organizational patching policies to determine compliance status. Returns detailed build information including service pack level, cumulative update, reference KB, and end-of-support dates with a compliance flag. Helps DBAs audit patch levels across environments and identify instances that fall below minimum security or stability requirements. You can test against specific minimum builds, relative currency policies (like "no more than 1 SP behind"), or require the latest available build.

    .PARAMETER Build
        Specifies one or more SQL Server build version numbers to test for compliance instead of connecting to live instances.
        Use this when you want to check specific build versions like "12.0.5540" without querying actual servers.
        Accepts version strings in the format major.minor.build or major.minor.build.revision.

    .PARAMETER MinimumBuild
        Sets the baseline build version that defines compliance requirements for your environment.
        Any SQL Server instance running a build version below this threshold will be flagged as non-compliant.
        Commonly used to enforce minimum security patch levels across your SQL Server estate.

    .PARAMETER MaxBehind
        Defines compliance based on how many service packs or cumulative updates behind the latest release is acceptable.
        Use format like "1SP", "2CU", or "1SP 1CU" to specify maximum allowed gaps from current releases.
        This approach automatically adjusts compliance targets as new patches are released, unlike fixed MinimumBuild values.

    .PARAMETER Latest
        Requires SQL Server instances to be running the most current build available for their version.
        Use this for environments with strict currency requirements where any outdated build is considered non-compliant.
        Automatically determines the latest available build for each SQL Server major version.

    .PARAMETER SqlInstance
        Target any number of instances, in order to return their compliance state.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Update
        Downloads the latest SQL Server build reference data from online sources before performing compliance checks.
        Use this periodically to ensure your compliance testing includes recently released patches and cumulative updates.
        The updated reference data is cached locally for subsequent function calls.

    .PARAMETER Quiet
        Returns only boolean compliance results ($true/$false) instead of detailed build information objects.
        Designed for use in automated scripts where you only need to know pass/fail status.
        Useful for integration with monitoring systems or compliance dashboards.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: SqlBuild, Version, Utility
        Author: Simone Bizzotto (@niphold) | Friedrich Weinmann (@FredWeinmann)

        dbatools PowerShell module (https://dbatools.io)
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .OUTPUTS
        System.Boolean (when -Quiet parameter is specified)

        Returns only the compliance result: $true if the build is compliant, $false if non-compliant. Designed for automated scripts and monitoring system integration.

        PSCustomObject (default)

        Returns one build compliance object per build version tested. The object includes build information and compliance status with the following properties:

        Always included:
        - Build: The SQL Server build version being tested
        - MatchType: How the build was matched - "Exact" for recognized builds or "Approximate" for unrecognized versions
        - Compliant: Boolean indicating if the build meets the specified compliance requirement ($true or $false)

        When -MinimumBuild is specified:
        - MinimumBuild: The baseline build version that was used for comparison
        - SPTarget, CUTarget, BuildTarget: Hidden (not shown by default)

        When -MaxBehind or -Latest is specified:
        - MaxBehind: The maximum allowed gap specification (e.g., "1SP", "2CU", "1SP 1CU") or empty for -Latest
        - SPTarget: Target Service Pack level required for compliance (null when -Latest or -MaxBehind uses only CU specification)
        - CUTarget: Target Cumulative Update level required for compliance (null when -Latest or -MaxBehind uses only SP specification)
        - BuildTarget: The target build version that represents the compliance threshold
        - MinimumBuild: Hidden (not shown by default)

        When -SqlInstance is specified (instead of -Build):
        - SqlInstance: The source SQL Server instance where the build was discovered

        When -SqlInstance is not specified (using -Build):
        - SqlInstance: Hidden (not shown by default)

        All properties can be accessed using Select-Object * regardless of the default display.

    .LINK
        https://dbatools.io/Test-DbaBuild

    .EXAMPLE
        PS C:\> Test-DbaBuild -Build "12.0.5540" -MinimumBuild "12.0.5557"

        Returns information about a build identified by "12.0.5540" (which is SQL 2014 with SP2 and CU4), which is not compliant as the minimum required
        build is "12.0.5557" (which is SQL 2014 with SP2 and CU8).

    .EXAMPLE
        PS C:\> Test-DbaBuild -Build "12.0.5540" -MaxBehind "1SP"

        Returns information about a build identified by "12.0.5540", making sure it is AT MOST 1 Service Pack "behind". For that version,
        that identifies an SP2, means accepting as the lowest compliance version as "12.0.4110", that identifies 2014 with SP1.

        Output column CUTarget is not relevant (empty). SPTarget and BuildTarget are filled in the result.

    .EXAMPLE
        PS C:\> Test-DbaBuild -Build "12.0.5540" -MaxBehind "1SP 1CU"

        Returns information about a build identified by "12.0.5540", making sure it is AT MOST 1 Service Pack "behind", plus 1 CU "behind". For that version,
        that identifies an SP2 and CU, rolling back 1 SP brings you to "12.0.4110", but given the latest CU for SP1 is CU13, the target "compliant" build
        will be "12.0.4511", which is 2014 with SP1 and CU12.

    .EXAMPLE
        PS C:\> Test-DbaBuild -Build "12.0.5540" -MaxBehind "0CU"

        Returns information about a build identified by "12.0.5540", making sure it is the latest CU release.

        Output columns CUTarget, SPTarget and BuildTarget are relevant. If the latest build is a service pack (not a CU), CUTarget will be empty.

    .EXAMPLE
        PS C:\> Test-DbaBuild -Build "12.0.5540" -Latest

        Returns information about a build identified by "12.0.5540", making sure it is the latest build available.

        Output columns CUTarget and SPTarget are not relevant (empty), only the BuildTarget is.

    .EXAMPLE
        PS C:\> Test-DbaBuild -Build "12.00.4502" -MinimumBuild "12.0.4511" -Update

        Same as before, but tries to fetch the most up to date index online. When the online version is newer, the local one gets overwritten.

    .EXAMPLE
        PS C:\> Test-DbaBuild -Build "12.0.4502","10.50.4260" -MinimumBuild "12.0.4511"

        Returns information builds identified by these versions strings.

    .EXAMPLE
        PS C:\> Get-DbaRegServer -SqlInstance sqlserver2014a | Test-DbaBuild -MinimumBuild "12.0.4511"

        Integrate with other cmdlets to have builds checked for all your registered servers on sqlserver2014a.

    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseShouldProcessForStateChangingFunctions", "")]
    [CmdletBinding()]
    param (
        [version[]]$Build,
        [version]$MinimumBuild,
        [string]$MaxBehind,
        [switch] $Latest,
        [parameter(ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [switch]$Update,
        [switch]$Quiet,
        [switch]$EnableException
    )

    begin {
        #region Helper functions
        function Get-DbaBuildReferenceIndex {
            [CmdletBinding()]

            $DbatoolsData = Get-DbatoolsConfigValue -Name 'Path.DbatoolsData'
            $writable_idxfile = Join-Path $DbatoolsData "dbatools-buildref-index.json"
            $result = Get-Content $writable_idxfile -Raw | ConvertFrom-Json
            $result.Data | Select-Object @{ Name = "VersionObject"; Expression = { [version]$_.Version } }, *
        }

        $ComplianceSpec = @()
        $ComplianceSpecExclusiveParams = @('MinimumBuild', 'MaxBehind', 'Latest')
        foreach ($exclParam in $ComplianceSpecExclusiveParams) {
            if (Test-Bound -Parameter $exclParam) { $ComplianceSpec += $exclParam }
        }
        if ($ComplianceSpec.Length -gt 1) {
            Stop-Function -Category InvalidArgument -Message "-MinimumBuild, -MaxBehind and -Latest are mutually exclusive. Please choose only one. Quitting."
            return
        }
        if ($ComplianceSpec.Length -eq 0) {
            Stop-Function -Category InvalidArgument -Message "You need to choose one from -MinimumBuild, -MaxBehind and -Latest. Quitting."
            return
        }
        if ($MaxBehind) {
            $MaxBehindValidator = [regex]'^(?<howmany>[\d]+)(?<what>SP|CU)$'
            $pieces = $MaxBehind.Split(' ') | Where-Object { $_ }
            try {
                $ParsedMaxBehind = @{ }
                foreach ($piece in $pieces) {
                    $pieceMatch = $MaxBehindValidator.Match($piece)
                    if ($pieceMatch.Success -ne $true) {
                        Stop-Function -Message "MaxBehind has an invalid syntax ('$piece' could not be parsed correctly)" -ErrorRecord $_
                        return
                    } else {
                        $howmany = [int]$pieceMatch.Groups['howmany'].Value
                        $what = $pieceMatch.Groups['what'].Value
                        if ($ParsedMaxBehind.ContainsKey($what)) {
                            Stop-Function -Message "The specifier $what has been already passed" -ErrorRecord $_
                            return
                        } else {
                            $ParsedMaxBehind[$what] = $howmany
                        }
                    }
                }
                if (-not $ParsedMaxBehind.ContainsKey('SP')) {
                    $ParsedMaxBehind['SP'] = 0
                }
            } catch {
                Stop-Function -Message "Error parsing MaxBehind" -ErrorRecord $_
                return
            }
        }
    }
    process {
        if (Test-FunctionInterrupt) { return }
        $hiddenProps = @()
        if (-not $SqlInstance) {
            $hiddenProps += 'SqlInstance'
        }
        if ($MinimumBuild) {
            $hiddenProps += 'MaxBehind', 'SPTarget', 'CUTarget', 'BuildTarget'
        } elseif ($MaxBehind -or $Latest) {
            $hiddenProps += 'MinimumBuild'
        }
        if ($Build) {
            $BuildVersions = Get-DbaBuild -Build $Build -Update:$Update -EnableException:$EnableException
        } elseif ($SqlInstance) {
            $BuildVersions = Get-DbaBuild -SqlInstance $SqlInstance -SqlCredential $SqlCredential -Update:$Update -EnableException:$EnableException
        }
        # Moving it down here to only trigger after -Update was properly called
        if (!$IdxRef) {
            try {
                $IdxRef = Get-DbaBuildReferenceIndex
            } catch {
                Stop-Function -Message "Error loading SQL build reference" -ErrorRecord $_
                return
            }
        }
        foreach ($BuildVersion in $BuildVersions) {
            $inputbuild = $BuildVersion.Build
            $compliant = $false
            $targetSPName = $null
            $targetCUName = $null
            if ($BuildVersion.MatchType -eq 'Approximate') {
                Write-Message -Level Warning -Message "$($BuildVersion.Build) is not recognized as a correct version"
            }
            if ($MinimumBuild) {
                Write-Message -Level Debug -Message "Comparing $MinimumBuild to $inputbuild"
                if ($inputbuild -ge $MinimumBuild) {
                    $compliant = $true
                }
            } elseif ($MaxBehind -or $Latest) {
                $buildAnchor = "$($inputbuild.Major).$($inputbuild.Minor).*"
                if ($inputbuild.Minor -notin (0, 50)) {
                    $buildAnchor = "$($inputbuild.Major).$($inputbuild.Minor - $inputbuild.Minor % 10).*"
                    Write-Message -Level Debug -Message "Normalized Minor Version to account version aliases"
                }
                $IdxVersion = $IdxRef | Where-Object Version -Like $buildAnchor
                $lastsp = ''
                $SPsAndCUs = @()
                foreach ($el in $IdxVersion) {
                    if ($null -ne $el.SP) {
                        $lastsp = $el.SP | Where-Object { $_ -ne 'LATEST' }
                        $SPsAndCUs += @{
                            VersionObject = $el.VersionObject
                            SP            = $lastsp
                        }
                    }
                    if ($null -ne $el.CU) {
                        $SPsAndCUs += @{
                            VersionObject = $el.VersionObject
                            SP            = $lastsp
                            CU            = $el.CU
                            Retired       = $el.Retired
                        }
                    }
                }
                $targetedBuild = $SPsAndCUs[0]
                if ($Latest) {
                    $targetedBuild = $IdxVersion[$IdxVersion.Length - 1]
                } else {
                    if ($ParsedMaxBehind.ContainsKey('SP')) {
                        [string[]]$AllSPs = $SPsAndCUs.SP | Select-Object -Unique
                        $targetSP = $AllSPs.Length - $ParsedMaxBehind['SP'] - 1
                        if ($targetSP -lt 0) {
                            $targetSP = 0
                        }
                        $targetSPName = $AllSPs[$targetSP]
                        Write-Message -Level Debug -Message "Target SP is $targetSPName - $targetSP on $($AllSPs.Length)"
                        $targetedBuild = $SPsAndCUs | Where-Object SP -eq $targetSPName | Select-Object -First 1
                    }
                    if ($ParsedMaxBehind.ContainsKey('CU')) {
                        [string[]]$AllCUs = ($SPsAndCUs | Where-Object VersionObject -GT $targetedBuild.VersionObject | Where-Object Retired -ne $true).CU | Select-Object -Unique
                        if ($AllCUs.Length -gt 0) {
                            #CU after the targeted build available
                            $targetCU = $AllCUs.Length - $ParsedMaxBehind['CU'] - 1
                            if ($targetCU -lt 0) {
                                $targetCU = 0
                            }
                            $targetCUName = $AllCUs[$targetCU]
                            Write-Message -Level Debug -Message "Target CU is $targetCUName - $targetCU on $($AllCUs.Length)"
                            $targetedBuild = $SPsAndCUs | Where-Object VersionObject -gt $targetedBuild.VersionObject | Where-Object CU -eq $targetCUName | Select-Object -First 1
                        }
                    }
                }
                if ($inputbuild -ge $targetedBuild.VersionObject) {
                    $compliant = $true
                }
            }
            Add-Member -InputObject $BuildVersion -MemberType NoteProperty -Name Compliant -Value $compliant
            Add-Member -InputObject $BuildVersion -MemberType NoteProperty -Name MinimumBuild -Value $MinimumBuild
            Add-Member -InputObject $BuildVersion -MemberType NoteProperty -Name MaxBehind -Value $MaxBehind
            Add-Member -InputObject $BuildVersion -MemberType NoteProperty -Name SPTarget -Value $targetSPName
            Add-Member -InputObject $BuildVersion -MemberType NoteProperty -Name CUTarget -Value $targetCUName
            Add-Member -InputObject $BuildVersion -MemberType NoteProperty -Name BuildTarget -Value $targetedBuild.VersionObject
            if ($Quiet) {
                $BuildVersion.Compliant
            } else {
                $BuildVersion | Select-Object * | Select-DefaultView -ExcludeProperty $hiddenProps
            }
        }
    }
}