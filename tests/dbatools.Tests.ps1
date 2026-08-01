#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools"
)
#$ManifestPath = "$ModulePath\$ModuleName.psd1"

Describe "$ModuleName Aliases" -Tag Aliases, Build {
    BeforeAll {
        $ModulePath = Split-Path $PSScriptRoot -Parent
    }

    It "declared aliases and their target commands exist" {
        ## Get the Aliases that should -Be set from the psm1 file
        $psm1 = Get-Content "$ModulePath\$ModuleName.psm1"
        $aliasMatches = [regex]::Matches($psm1, "AliasName`"\s*=\s*`"(\w*-\w*)`"")
        $aliases = foreach ($aliasMatch in $aliasMatches) {
            $aliasMatch.Groups[1].Value
        }
        $aliasErrors = foreach ($alias in $aliases) {
            $aliasInfo = Get-Alias $alias -ErrorAction SilentlyContinue
            if (-not $aliasInfo) {
                "Alias $alias does not exist"
            } elseif (-not (Get-Command $aliasInfo.Definition -ErrorAction SilentlyContinue)) {
                "Alias $alias targets missing command $($aliasInfo.Definition)"
            }
        }

        $aliasErrors | Should -BeNullOrEmpty
    }
}

Describe "$ModuleName TEPP asynchronous cache" -Tag UnitTests {
    <#
    The asynchronous TEPP cache runspace imports a second copy of dbatools and reconnects to every
    instance the session has touched, every few minutes, for as long as the session lives. A
    scheduled task or a build agent never tab completes anything, so it gets those connections for
    nothing. Importing the module must therefore register the runspace without starting it, and the
    first tab completion must start it. Since a tab completion is now what starts it, both opt-outs
    have to survive one rather than be undone by it, and anyone who wants the old start-at-import
    behaviour back has to be able to ask for it.

    These are read out of a fresh PowerShell, because the runspace starts at most once per process.
    Asserting inside this one would depend on whether an earlier test file happened to start it.
    #>
    BeforeAll {
        $ModulePath = Split-Path $PSScriptRoot -Parent

        $teppProbePath = Join-Path ([System.IO.Path]::GetTempPath()) "dbatools-teppasync-$(Get-Random)"
        $null = New-Item -Path $teppProbePath -ItemType Directory

        # The probe lives in a file so nothing has to survive a round trip through nested command
        # line quoting.
        $teppProbeScript = Join-Path $teppProbePath "teppasync-probe.ps1"
        Set-Content -Path $teppProbeScript -Value @'
param(
    $ModulePath
)

# Report on the module's behaviour, not on whatever this machine has persisted or exported. The
# $global:dbatools_config scriptblock is invoked during import, after persisted configuration has
# been read and well before the asynchronous cache script runs, so it decides the settings the
# module imports with. Without it a contributor who has switched TEPP off would see these fail.
Remove-Item -Path Env:\DBATOOLS_DISABLE_TEPP -ErrorAction SilentlyContinue
$global:dbatools_config = {
    Set-DbatoolsConfig -FullName "TabExpansion.Disable" -Value $false
    Set-DbatoolsConfig -FullName "TabExpansion.Disable.Asynchronous" -Value $false
}

Import-Module (Join-Path $ModulePath "dbatools.psd1") -ErrorAction Stop

Remove-Variable -Name dbatools_config -Scope Global

function Get-AsyncCacheState {
    $asyncCacheRunspace = [Dataplat.Dbatools.Runspace.RunspaceHost]::Runspaces["dbatools-teppasynccache"]
    if ($null -eq $asyncCacheRunspace) {
        return "NotRegistered"
    }
    return $asyncCacheRunspace.State
}

# Reported alongside the states so that a failure carries the settings that decide it.
"TeppDisabled=$([Dataplat.Dbatools.TabExpansion.TabExpansionHost]::TeppDisabled)"
"TeppAsyncDisabled=$([Dataplat.Dbatools.TabExpansion.TabExpansionHost]::TeppAsyncDisabled)"

"AfterImport=$(Get-AsyncCacheState)"

# TabExpansion2 is the completion entry point the console calls when someone presses Tab, so this
# drives the real completer rather than reaching into the module.
$teppCompletionInput = "Get-DbaDatabase -Database "
$null = TabExpansion2 -inputScript $teppCompletionInput -cursorColumn $teppCompletionInput.Length

"AfterCompletion=$(Get-AsyncCacheState)"

# Someone who switches the cache off has to stay switched off. Now that a tab completion is what
# starts the runspace, the opt-out has to survive one rather than be undone by it.
Set-DbatoolsConfig -FullName "TabExpansion.Disable.Asynchronous" -Value $true

"AfterOptOut=$(Get-AsyncCacheState)"

$null = TabExpansion2 -inputScript $teppCompletionInput -cursorColumn $teppCompletionInput.Length

"AfterOptOutCompletion=$(Get-AsyncCacheState)"

# Switching it back on must not start it either, since enabling TEPP and starting the cache are
# separate decisions now. The completion after it has to work, so that a container which has
# already run once can be started again rather than being spent.
Set-DbatoolsConfig -FullName "TabExpansion.Disable.Asynchronous" -Value $false

"AfterReEnable=$(Get-AsyncCacheState)"

$null = TabExpansion2 -inputScript $teppCompletionInput -cursorColumn $teppCompletionInput.Length

"AfterReEnableCompletion=$(Get-AsyncCacheState)"

# The global switch is the one most people reach for and it runs a different handler, so it gets
# its own case. The asynchronous switch is on at this point, so the global one holds on its own.
Set-DbatoolsConfig -FullName "TabExpansion.Disable" -Value $true

$null = TabExpansion2 -inputScript $teppCompletionInput -cursorColumn $teppCompletionInput.Length

"AfterGlobalDisableCompletion=$(Get-AsyncCacheState)"
'@

        $teppProbeHost = (Get-Process -Id $PID).Path
        $teppProbeOutput = & $teppProbeHost -NoProfile -NonInteractive -File $teppProbeScript -ModulePath $ModulePath 2>&1

        $teppImportLine = $teppProbeOutput | Where-Object { $PSItem -match "^AfterImport=" }
        $teppReEnableLine = $teppProbeOutput | Where-Object { $PSItem -match "^AfterReEnable=" }
        $teppCompletionLine = $teppProbeOutput | Where-Object { $PSItem -match "^AfterCompletion=" }
        $teppOptOutLine = $teppProbeOutput | Where-Object { $PSItem -match "^AfterOptOut=" }
        $teppOptOutCompletionLine = $teppProbeOutput | Where-Object { $PSItem -match "^AfterOptOutCompletion=" }
        $teppReEnableCompletionLine = $teppProbeOutput | Where-Object { $PSItem -match "^AfterReEnableCompletion=" }
        $teppGlobalDisableLine = $teppProbeOutput | Where-Object { $PSItem -match "^AfterGlobalDisableCompletion=" }
        $stateAfterImport = "$teppImportLine" -replace "^AfterImport=", ""
        $stateAfterReEnable = "$teppReEnableLine" -replace "^AfterReEnable=", ""
        $stateAfterReEnableCompletion = "$teppReEnableCompletionLine" -replace "^AfterReEnableCompletion=", ""
        $stateAfterCompletion = "$teppCompletionLine" -replace "^AfterCompletion=", ""
        $stateAfterOptOut = "$teppOptOutLine" -replace "^AfterOptOut=", ""
        $stateAfterOptOutCompletion = "$teppOptOutCompletionLine" -replace "^AfterOptOutCompletion=", ""
        $stateAfterGlobalDisable = "$teppGlobalDisableLine" -replace "^AfterGlobalDisableCompletion=", ""

        # Starting at import is an import-time decision, so the opt-in needs a process of its own.
        $teppStartProbeScript = Join-Path $teppProbePath "teppasync-startonimport-probe.ps1"
        Set-Content -Path $teppStartProbeScript -Value @'
param(
    $ModulePath
)

Remove-Item -Path Env:\DBATOOLS_DISABLE_TEPP -ErrorAction SilentlyContinue
$global:dbatools_config = {
    Set-DbatoolsConfig -FullName "TabExpansion.Disable" -Value $false
    Set-DbatoolsConfig -FullName "TabExpansion.Disable.Asynchronous" -Value $false
    Set-DbatoolsConfig -FullName "TabExpansion.Asynchronous.StartOnImport" -Value $true
}

Import-Module (Join-Path $ModulePath "dbatools.psd1") -ErrorAction Stop

Remove-Variable -Name dbatools_config -Scope Global

$asyncCacheRunspace = [Dataplat.Dbatools.Runspace.RunspaceHost]::Runspaces["dbatools-teppasynccache"]
if ($null -eq $asyncCacheRunspace) {
    "AfterImport=NotRegistered"
} else {
    "AfterImport=$($asyncCacheRunspace.State)"
}
'@

        $teppStartProbeOutput = & $teppProbeHost -NoProfile -NonInteractive -File $teppStartProbeScript -ModulePath $ModulePath 2>&1

        $teppStartImportLine = $teppStartProbeOutput | Where-Object { $PSItem -match "^AfterImport=" }
        $stateStartOnImport = "$teppStartImportLine" -replace "^AfterImport=", ""
    }

    AfterAll {
        Remove-Item -Path $teppProbePath -Recurse -ErrorAction SilentlyContinue
    }

    It "registers the asynchronous cache runspace on import" {
        # A missing runspace would let the next assertion pass for the wrong reason.
        $stateAfterImport | Should -Not -Be "NotRegistered" -Because "the probe reported: $teppProbeOutput"
    }

    It "does not start the asynchronous cache runspace on import" {
        $stateAfterImport | Should -Be "Stopped" -Because "the probe reported: $teppProbeOutput"
    }

    It "starts the asynchronous cache runspace on the first tab completion" {
        $stateAfterCompletion | Should -Be "Running" -Because "the probe reported: $teppProbeOutput"
    }

    It "stops the asynchronous cache runspace when it is switched off" {
        $stateAfterOptOut | Should -Be "Stopped" -Because "the probe reported: $teppProbeOutput"
    }

    It "does not restart the asynchronous cache runspace once it is switched off" {
        $stateAfterOptOutCompletion | Should -Be "Stopped" -Because "the probe reported: $teppProbeOutput"
    }

    It "does not start the asynchronous cache runspace when it is switched back on" {
        $stateAfterReEnable | Should -Be "Stopped" -Because "the probe reported: $teppProbeOutput"
    }

    It "starts the asynchronous cache runspace again after it has been switched back on" {
        $stateAfterReEnableCompletion | Should -Be "Running" -Because "the probe reported: $teppProbeOutput"
    }

    It "does not start the asynchronous cache runspace while TEPP is globally disabled" {
        $stateAfterGlobalDisable | Should -Be "Stopped" -Because "the probe reported: $teppProbeOutput"
    }

    It "starts the asynchronous cache runspace on import when asked to" {
        $stateStartOnImport | Should -Be "Running" -Because "the probe reported: $teppStartProbeOutput"
    }
}

Describe "$ModuleName style" -Tag Compliance {
    <#
    Ensures common formatting standards are applied:
    - OTBS style, courtesy of PSSA's Invoke-Formatter, is what dbatools uses
    - UTF8 without BOM is what is going to be used in PS Core, so we adopt this standard for dbatools
    #>
    BeforeAll {
        $ModulePath = Split-Path $PSScriptRoot -Parent
        $AllFiles = Get-ChildItem -Path $ModulePath -File -Recurse -Filter "*.ps*1" | Where-Object Name -ne "dbatools.ps1"
    }

    It "PowerShell files do not contain a UTF-8 BOM" {
        $bomFiles = foreach ($file in $AllFiles) {
            [byte[]]$byteContent = [System.IO.File]::ReadAllBytes($file.FullName)
            if ($byteContent.Length -gt 2 -and $byteContent[0] -eq 0xef -and $byteContent[1] -eq 0xbb -and $byteContent[2] -eq 0xbf) {
                $file.FullName
            }
        }

        $bomFiles | Should -BeNullOrEmpty
    }

    It "PowerShell files are not indented with tabs" {
        $leadingTabs = foreach ($file in $AllFiles) {
            foreach ($match in (Select-String -Path $file.FullName -Pattern "^[\t]+")) {
                "$($file.FullName):$($match.LineNumber)"
            }
        }

        $leadingTabs | Should -BeNullOrEmpty
    }

    It "PowerShell files do not contain trailing spaces" {
        $trailingSpaces = foreach ($file in $AllFiles) {
            foreach ($match in (Select-String -Path $file.FullName -Pattern "([^ \t\r\n])[ \t]+$")) {
                "$($file.FullName):$($match.LineNumber)"
            }
        }

        $trailingSpaces | Should -BeNullOrEmpty
    }
}

Describe "$ModuleName prohibited APIs" -Tag Compliance {
    <#
    Ensures avoiding already discovered pitfalls
    #>
    BeforeAll {
        $ModulePath = Split-Path $PSScriptRoot -Parent
        $AllPublicFunctions = Get-ChildItem -Path "$ModulePath\public" -Filter "*.ps*1"
    }

    It "public commands use Invoke-TlsWebRequest for compatible TLS" {
        # .NET defaults clash with recent TLS hardening (e.g. no TLS 1.2 by default)
        $notCompatible = foreach ($file in $AllPublicFunctions) {
            $notAllowed = Select-String -Path $file.FullName -Pattern "Invoke-WebRequest | New-Object System.Net.WebClient|\.DownloadFile"
            if ($notAllowed.Count -gt 0 -and $file.Name -notmatch "DbaKbUpdate") {
                $file.FullName
            }
        }

        $notCompatible | Should -BeNullOrEmpty
    }

    It "public commands do not use Shell.Application" {
        # Not every PS instance has Shell.Application
        $shellApplicationFiles = foreach ($file in $AllPublicFunctions) {
            if (Select-String -Path $file.FullName -Pattern "shell.application") {
                $file.FullName
            }
        }

        $shellApplicationFiles | Should -BeNullOrEmpty
    }
}

Describe "$ModuleName ScriptAnalyzerErrors" -Tag Compliance {
    BeforeAll {
        $ModulePath = Split-Path $PSScriptRoot -Parent
    }

    It "public and private functions have no ScriptAnalyzer errors" {
        $scriptAnalyzerErrors = @()
        $scriptAnalyzerErrors += Invoke-ScriptAnalyzer -Path "$ModulePath\public" -Severity Error
        $scriptAnalyzerErrors += Invoke-ScriptAnalyzer -Path "$ModulePath\private\functions" -Severity Error
        # Copy-DbaCredential intentionally converts a decrypted migration value immediately back to SecureString for New-DbaCredential.
        $scriptAnalyzerErrors = $scriptAnalyzerErrors | Where-Object {
            -not ($PSItem.RuleName -eq "PSAvoidUsingConvertToSecureStringWithPlainText" -and $PSItem.ScriptName -eq "Copy-DbaCredential.ps1")
        }

        $scriptAnalyzerErrors | Should -BeNullOrEmpty
    }
}

Describe "$ModuleName Tests missing" -Tag Tests {
    BeforeAll {
        $ModulePath = Split-Path $PSScriptRoot -Parent
        $functions = Get-ChildItem "$ModulePath\public\" -Recurse -Include "*.ps1"
    }

    It "every public function has a test file" {
        $missingTests = foreach ($file in $functions) {
            if (-not (Test-Path "$ModulePath\tests\$($file.BaseName).Tests.ps1")) {
                $file.BaseName
            }
        }

        $missingTests | Should -BeNullOrEmpty
    }

    It "every public function test has parameter validation" {
        $missingValidation = foreach ($file in $functions) {
            $testPath = "$ModulePath\tests\$($file.BaseName).Tests.ps1"
            if (Test-Path $testPath) {
                $testFile = Get-Content $testPath -Raw
                $hasValidation = $testFile -match "Context `"Validate parameters`"" -or $testFile -match "Context `"Parameter validation`""
                if (-not $hasValidation) {
                    $file.BaseName
                }
            }
        }

        $missingValidation | Should -BeNullOrEmpty
    }
}

Describe "$ModuleName Function Name" -Tag Compliance {
    BeforeAll {
        $ModulePath = Split-Path $PSScriptRoot -Parent
        $publicFunctions = Get-ChildItem -Path "$ModulePath\public" -Filter "*.ps*1"
        $privateFunctions = Get-ChildItem -Path "$ModulePath\private\functions" -Filter "*.ps*1" | Where-Object BaseName -ne "Where-DbaObject"
    }

    It "function names match their filenames" {
        $functionNameMatchesErrors = foreach ($item in @($publicFunctions) + @($privateFunctions)) {
            $tokens = $null
            $errors = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseFile($item.FullName, [ref]$tokens, [ref]$errors)
            $functionName = $ast.EndBlock.Statements.Name
            if ($functionName -cne $item.BaseName) {
                "$functionName is not equal to $($item.BaseName)"
            }
        }

        $functionNameMatchesErrors | Should -BeNullOrEmpty
    }

    It "public function names contain -Dba" {
        $functionNameDbaErrors = foreach ($item in $publicFunctions) {
            $tokens = $null
            $errors = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseFile($item.FullName, [ref]$tokens, [ref]$errors)
            $functionName = $ast.EndBlock.Statements.Name
            if ($functionName -notmatch "-Dba") {
                $functionName
            }
        }

        $functionNameDbaErrors | Should -BeNullOrEmpty
    }
}

# test the module manifest - exports the right functions, processes the right formats, and is generally correct
<#
Describe "Manifest" {

    $global:Manifest = $null

    It "has a valid manifest" {

        {

            $global:Manifest = Test-ModuleManifest -Path $ManifestPath -ErrorAction Stop -WarningAction SilentlyContinue

        } | Should -Not -Throw

    }
## Should -Be fixed now - Until the issue with requiring full paths for required assemblies is resolved need to keep this commented out RMS 01112016

$global:Manifest = Test-ModuleManifest -Path $ManifestPath -ErrorAction SilentlyContinue
    It "has a valid name" {

        $global:Manifest.Name | Should -Be $ModuleName

    }



    It "has a valid root module" {

        $global:Manifest.RootModule | Should -Be "$ModuleName.psm1"

    }



    It "has a valid Description" {

        $global:Manifest.Description | Should -Be 'Provides extra functionality for SQL Server Database admins and enables SQL Server instance migrations.'

    }

    It "has a valid Author" {
        $global:Manifest.Author | Should -Be 'Chrissy LeMaire'
    }

    It "has a valid Company Name" {
        $global:Manifest.CompanyName | Should -Be 'dbatools.io'
    }
    It "has a valid guid" {

        $global:Manifest.Guid | Should -Be '9d139310-ce45-41ce-8e8b-d76335aa1789'

    }
    It "has valid PowerShell version" {
        $global:Manifest.PowerShellVersion | Should -Be '3.0'
    }

    It "has valid  required assemblies" {
        $global:Manifest.RequiredAssemblies | Should -BeEmpty
    }

    It "has a valid copyright" {

        $global:Manifest.CopyRight | Should -BeLike '* Chrissy LeMaire'

    }



 # Don't want this just yet

    It 'exports all public functions' {

        $FunctionFiles = Get-ChildItem "$ModulePath\public" -Filter *.ps1 | Select-Object -ExpandProperty BaseName

        $FunctionNames = $FunctionFiles

        $ExFunctions = $global:Manifest.ExportedFunctions.Values.Name
        $ExFunctions
        foreach ($FunctionName in $FunctionNames)

        {

            $ExFunctions -contains $FunctionName | Should -Be $true

        }

    }
}
#>
