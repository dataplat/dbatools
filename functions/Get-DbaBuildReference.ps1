function Get-DbaBuildReference {
    <#
    .SYNOPSIS
        Returns SQL Server Build infos on a SQL instance

    .DESCRIPTION
        Returns info about the specific build of a SQL instance, including the SP, the CU and the reference KB, wherever possible.
        It also includes End Of Support dates as specified on Microsoft Life Cycle Policy

    .PARAMETER Build
        Instead of connecting to a real instance, pass a string identifying the build to get the info back.

    .PARAMETER Kb
        Get a KB information based on its number. Supported format: KBXXXXXX, or simply XXXXXX.

    .PARAMETER MajorVersion
        Get a KB information based on SQL Server version. Can be refined further by -ServicePack and -CumulativeUpdate parameters.
        Examples: SQL2008 | 2008R2 | 2016

    .PARAMETER ServicePack
        Get a KB information based on SQL Server Service Pack version. Can be refined further by -CumulativeUpdate parameter.
        Examples: SP0 | 2 | RTM

    .PARAMETER CumulativeUpdate
        Get a KB information based on SQL Server Cumulative Update version.
         Examples: CU0 | CU13 | CU0

    .PARAMETER SqlInstance
        Target any number of instances, in order to return their build state.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Update
        Adding this switch will look online for the most up to date reference, optionally replacing the local one.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: SqlBuild
        Author: Simone Bizzotto (@niphold) | Friedrich Weinmann (@FredWeinmann)

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaBuildReference

    .EXAMPLE
        PS C:\> Get-DbaBuildReference -Build "12.00.4502"

        Returns information about a build identified by  "12.00.4502" (which is SQL 2014 with SP1 and CU11)

    .EXAMPLE
        PS C:\> Get-DbaBuildReference -Build "12.00.4502" -Update

        Returns information about a build trying to fetch the most up to date index online. When the online version is newer, the local one gets overwritten

    .EXAMPLE
        PS C:\> Get-DbaBuildReference -Build "12.0.4502","10.50.4260"

        Returns information builds identified by these versions strings

    .EXAMPLE
        PS C:\> Get-DbaRegServer -SqlInstance sqlserver2014a | Get-DbaBuildReference

        Integrate with other cmdlets to have builds checked for all your registered servers on sqlserver2014a

    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseShouldProcessForStateChangingFunctions", "")]
    [CmdletBinding(DefaultParameterSetName = 'Build')]
    param (
        [version[]]
        $Build,

        [string[]]
        $Kb,

        [ValidateNotNullOrEmpty()]
        [string]
        $MajorVersion,

        [ValidateNotNullOrEmpty()]
        [string]
        [Alias('SP')]
        $ServicePack = 'RTM',

        [string]
        [Alias('CU')]
        $CumulativeUpdate,

        [Parameter(ValueFromPipeline)]
        [DbaInstanceParameter[]]
        $SqlInstance,

        [PsCredential]
        $SqlCredential,

        [switch]
        $Update,

        [switch]$EnableException
    )

    begin {

        #region verifying parameters
        $isPipelineSqlInstance = $PSCmdlet.MyInvocation.ExpectingInput
        $ComplianceSpec = @()
        $ComplianceSpecExclusiveParams = @('Build', 'Kb', @( 'MajorVersion', 'ServicePack', 'CumulativeUpdate'), 'SqlInstance')
        foreach ($exclParamGroup in $ComplianceSpecExclusiveParams) {
            foreach ($exclParam in $exclParamGroup) {
                if ($exclParam -eq 'SqlInstance') {
                    if ($isPipelineSqlInstance -or (Test-Bound -ParameterName 'SqlInstance')) {
                        $ComplianceSpec += $exclParam
                    }
                } else {
                    if (Test-Bound -ParameterName $exclParam) {
                        $ComplianceSpec += $exclParam
                        break
                    }
                }
            }
        }
        if ($ComplianceSpec.Length -eq 0 -and (Test-Bound -Not -ParameterName 'Update') -and (-not($isPipelineSqlInstance))) {
            Stop-Function -Category InvalidArgument -Message "You need to choose at least one parameter."
            return
        }
        if ($ComplianceSpec.Length -gt 1) {
            Stop-Function -Category InvalidArgument -Message "$($ComplianceSpec -join ', ') are mutually exclusive. Please choose one or the other. Quitting."
            return
        }
        if (((Test-Bound -ParameterName 'ServicePack') -or (Test-Bound -ParameterName 'CumulativeUpdate')) -and (Test-Bound -Not -ParameterName 'MajorVersion')) {
            Stop-Function -Category InvalidArgument -Message "-MajorVersion is required when specifying SP or CU."
            return
        }
        if ($MajorVersion) {
            if ($MajorVersion -match '^(SQL)?(\d{4}(R2)?)$') {
                $MajorVersion = $Matches[2]
            } else {
                Stop-Function -Message "Incorrect SQL Server version format: use SQL2XXX or just 2XXXX - SQL2012, SQL2008R2"
                return
            }
            if (!$ServicePack) {
                $ServicePack = 'RTM'
            }
            if ($ServicePack -match '^(SP)?\s*(\d+)$') {
                if ($Matches[2] -eq '0') {
                    $ServicePack = 'RTM'
                } else {
                    $ServicePack = 'SP' + $Matches[2]
                }
            } elseif ($ServicePack -notmatch '^RTM$') {
                Stop-Function -Message "Incorrect SQL Server service pack format: use SPX, X or RTM, where X is a service pack number"
                return
            }
            if ($CumulativeUpdate) {
                if ($CumulativeUpdate -match '^(CU)?\s*(\d+)$') {
                    if ($Matches[2] -eq '0') {
                        $CumulativeUpdate = ''
                    } else {
                        $CumulativeUpdate = 'CU' + $Matches[2]
                    }
                } else {
                    Stop-Function -Message "Incorrect SQL Server cumulative update format: use CUX or X, where X is a cumulative update number"
                    return
                }
            }
        }
        #endregion verifying parameters

        #region Helper functions
        function Get-DbaBuildReferenceIndex {
            [CmdletBinding()]
            param (
                [string]
                $Moduledirectory,

                [bool]
                $Update,

                [bool]
                $EnableException
            )

            $orig_idxfile = Resolve-Path "$Moduledirectory\bin\dbatools-buildref-index.json"
            $DbatoolsData = Get-DbatoolsConfigValue -Name 'Path.DbatoolsData'
            $writable_idxfile = Join-Path $DbatoolsData "dbatools-buildref-index.json"

            if (-not (Test-Path $orig_idxfile)) {
                Write-Message -Level Warning -Message "Unable to read local SQL build reference file. Please check your module integrity or reinstall dbatools."
            }

            if ((-not (Test-Path $orig_idxfile)) -and (-not (Test-Path $writable_idxfile))) {
                throw "Build reference file not found, please check module health."
            }

            # If no writable copy exists, create one and return the module original
            if (-not (Test-Path $writable_idxfile)) {
                Copy-Item -Path $orig_idxfile -Destination $writable_idxfile -Force -ErrorAction Stop
                $result = Get-Content $orig_idxfile -Raw | ConvertFrom-Json
            }

            # Else, if both exist, update the writeable if necessary and return the current version
            elseif (Test-Path $orig_idxfile) {
                $module_content = Get-Content $orig_idxfile -Raw | ConvertFrom-Json
                $data_content = Get-Content $writable_idxfile -Raw | ConvertFrom-Json

                $module_time = Get-Date $module_content.LastUpdated
                $data_time = Get-Date $data_content.LastUpdated

                if ($module_time -gt $data_time) {
                    Copy-Item -Path $orig_idxfile -Destination $writable_idxfile -Force -ErrorAction Stop
                    $result = $module_content
                } else {
                    $result = $data_content
                }
                # If Update is passed, try to fetch from online resource and store into the writeable
                if ($Update) {
                    Update-DbaBuildReference -EnableException -ErrorAction Stop
                }
            }

            # Else if the module version of the file no longer exists, but the writable version exists, return the writable version
            else {
                $result = Get-Content $writable_idxfile -Raw | ConvertFrom-Json
            }

            $LastUpdated = Get-Date -Date $result.LastUpdated
            if ($LastUpdated -lt (Get-Date).AddDays(-45)) {
                Write-Message -Level Warning -Message "Index is stale, last update on: $(Get-Date -Date $LastUpdated -Format s), try the -Update parameter to fetch the most up to date index"
            }

            $result.Data | Select-Object @{ Name = "VersionObject"; Expression = { [version]$_.Version } }, *
        }


        function Resolve-DbaBuild {
            [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseShouldProcessForStateChangingFunctions", "")]
            [CmdletBinding()]
            [OutputType([System.Collections.Hashtable])]
            param (
                [Parameter(Mandatory, ParameterSetName = 'Build')]
                [version]
                $Build,

                [Parameter(Mandatory, ParameterSetName = 'KB')]
                [string]
                $Kb,

                [Parameter(Mandatory, ParameterSetName = 'HFLevel')]
                [string]
                $MajorVersion,

                [Parameter(ParameterSetName = 'HFLevel')]
                [string]
                [Alias('SP')]
                $ServicePack = 'RTM',

                [Parameter(ParameterSetName = 'HFLevel')]
                [string]
                [Alias('CU')]
                $CumulativeUpdate,

                $Data,

                [bool]
                $EnableException
            )

            if ($Build) {
                Write-Message -Level Verbose -Message "Looking for $Build"

                $IdxVersion = $Data | Where-Object Version -like "$($Build.Major).$($Build.Minor).*"
            } elseif ($Kb) {
                Write-Message -Level Verbose -Message "Looking for KB $Kb"
                if ($Kb -match '^(KB)?(\d+)$') {
                    $currentKb = $Matches[2]
                    $kbVersion = $Data | Where-Object KBList -contains $currentKb
                    $IdxVersion = $Data | Where-Object Version -like "$($kbVersion.VersionObject.Major).$($kbVersion.VersionObject.Minor).*"
                } else {
                    Stop-Function -Message "Wrong KB name $kb"
                    return
                }
            } elseif ($MajorVersion) {
                Write-Message -Level Verbose -Message "Looking for SQL $MajorVersion SP $ServicePack CU $CumulativeUpdate"
                $kbVersion = $Data | Where-Object Name -eq $MajorVersion
                $IdxVersion = $Data | Where-Object Version -like "$($kbVersion.VersionObject.Major).$($kbVersion.VersionObject.Minor).*"
            }

            $Detected = @{ }
            $Detected.MatchType = 'Approximate'
            $idxCount = $IdxVersion | Measure-Object | Select-Object -ExpandProperty Count
            Write-Message -Level Verbose -Message "We have $idxCount builds in store for this Release"
            If ($idxCount -eq 0) {
                Write-Message -Level Warning -Message "No info in store for this Release"
                $Detected.Warning = "No info in store for this Release"
            } else {
                $LastVer = $IdxVersion[0]
            }
            foreach ($el in $IdxVersion) {
                if ($null -ne $el.Name) {
                    $Detected.Name = $el.Name
                }
                if ($Build -and $el.VersionObject -gt $Build) {
                    $Detected.MatchType = 'Approximate'
                    $Detected.Warning = "$Build not found, closest build we have is $($LastVer.Version)"
                    break
                }
                $LastVer = $el
                $Detected.BuildLevel = $el.VersionObject
                if ($null -ne $el.SP) {
                    $Detected.SP = $el.SP
                    $Detected.CU = $null
                }
                if ($null -ne $el.CU) {
                    $Detected.CU = $el.CU
                }
                if ($null -ne $el.SupportedUntil) {
                    $Detected.SupportedUntil = (Get-Date -date $el.SupportedUntil)
                }
                $Detected.Build = $el.Version
                $Detected.KB = $el.KBList
                if (($Build -and $el.Version -eq $Build) -or ($Kb -and $el.KBList -eq $currentKb)) {
                    $Detected.MatchType = 'Exact'
                    if ($el.Retired) {
                        $Detected.Warning = "This version has been officially retired by Microsoft"
                    }
                    break
                } elseif ($MajorVersion -and $Detected.SP -contains $ServicePack -and (!$CumulativeUpdate -or ($el.CU -and $el.CU -eq $CumulativeUpdate))) {
                    $Detected.MatchType = 'Exact'
                    if ($el.Retired) {
                        $Detected.Warning = "This version has been officially retired by Microsoft"
                    }
                    break
                }
            }
            return $Detected
        }
        #endregion Helper functions

        $moduledirectory = $script:PSModuleRoot

        try {
            $IdxRef = Get-DbaBuildReferenceIndex -Moduledirectory $moduledirectory -Update $Update -EnableException $EnableException
        } catch {
            Stop-Function -Message "Error loading SQL build reference" -ErrorRecord $_
            return
        }
    }
    process {

        if (Test-FunctionInterrupt) { return }

        foreach ($instance in $SqlInstance) {
            #region Ensure the connection is established
            try {
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Failed to process Instance $Instance" -ErrorRecord $_ -Target $instance -Continue
            }

            try {
                $null = $server.Version.ToString()
            } catch {
                Stop-Function -Message "Error occurred while establishing connection to $instance" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }
            #endregion Ensure the connection is established

            $Detected = Resolve-DbaBuild -Build $server.Version -Data $IdxRef -EnableException $EnableException

            [PSCustomObject]@{
                SqlInstance    = $server.DomainInstanceName
                Build          = $server.Version
                NameLevel      = $Detected.Name
                SPLevel        = $Detected.SP
                CULevel        = $Detected.CU
                KBLevel        = $Detected.KB
                BuildLevel     = $Detected.BuildLevel
                SupportedUntil = $Detected.SupportedUntil
                MatchType      = $Detected.MatchType
                Warning        = $Detected.Warning
            }
        }

        foreach ($buildstr in $Build) {
            $Detected = Resolve-DbaBuild -Build $buildstr -Data $IdxRef -EnableException $EnableException

            [PSCustomObject]@{
                SqlInstance    = $null
                Build          = $buildstr
                NameLevel      = $Detected.Name
                SPLevel        = $Detected.SP
                CULevel        = $Detected.CU
                KBLevel        = $Detected.KB
                BuildLevel     = $Detected.BuildLevel
                SupportedUntil = $Detected.SupportedUntil
                MatchType      = $Detected.MatchType
                Warning        = $Detected.Warning
            } | Select-DefaultView -ExcludeProperty SqlInstance
        }

        foreach ($kbItem in $Kb) {
            $Detected = Resolve-DbaBuild -Kb $kbItem -Data $IdxRef -EnableException $EnableException

            [PSCustomObject]@{
                SqlInstance    = $null
                Build          = $Detected.Build
                NameLevel      = $Detected.Name
                SPLevel        = $Detected.SP
                CULevel        = $Detected.CU
                KBLevel        = $Detected.KB
                BuildLevel     = $Detected.BuildLevel
                SupportedUntil = $Detected.SupportedUntil
                MatchType      = $Detected.MatchType
                Warning        = $Detected.Warning
            } | Select-DefaultView -ExcludeProperty SqlInstance
        }

        if ($MajorVersion) {
            $Detected = Resolve-DbaBuild -MajorVersion $MajorVersion -ServicePack $ServicePack -CumulativeUpdate $CumulativeUpdate -Data $IdxRef -EnableException $EnableException

            [PSCustomObject]@{
                SqlInstance    = $null
                Build          = $Detected.Build
                NameLevel      = $Detected.Name
                SPLevel        = $Detected.SP
                CULevel        = $Detected.CU
                KBLevel        = $Detected.KB
                BuildLevel     = $Detected.BuildLevel
                SupportedUntil = $Detected.SupportedUntil
                MatchType      = $Detected.MatchType
                Warning        = $Detected.Warning
            } | Select-DefaultView -ExcludeProperty SqlInstance
        }
    }
}