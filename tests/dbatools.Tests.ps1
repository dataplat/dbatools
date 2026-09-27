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

Describe "$ModuleName test file structure" -Tag Compliance {
    <#
    Static checks over tests\*.Tests.ps1, so that a test file that cannot do its job is caught here
    rather than by someone eventually noticing.

    Several of these are not style. A loop that emits It blocks, a -ForEach fed from a BeforeAll and
    an assertion that is never piped to Should all produce a green test report while testing nothing
    at all - Update-DbaInstance.Tests.ps1 carried 44 such tests for years.

    The findings are collected per rule rather than asserted per file. The per-file form produces one
    test result for every rule and every file, which is 14000 results and two and a half minutes; the
    failure message still names every file it found.

    The checks tagged Goal are the ones the tree does not meet yet, so they are skipped unless
    $env:DbatoolsTestFileGoals is set. To work on that backlog:
        $env:DbatoolsTestFileGoals = 1
        Invoke-Pester -Path .\tests\dbatools.Tests.ps1 -TagFilter Compliance
    #>
    BeforeDiscovery {
        # -Skip: is read while the tests are discovered, so the switch cannot come from a BeforeAll.
        $includeGoals = [bool]$env:DbatoolsTestFileGoals
    }

    BeforeAll {
        $ModulePath = Split-Path $PSScriptRoot -Parent

        # The only files in tests\ that are not the test of a single command, so the only ones that
        # cannot follow the layout. Everything else - including the tests of private functions like
        # Stop-Function - can and does.
        $notACommandTest = @(
            "appveyor.common.Tests.ps1",
            "appveyor.watchdog.Tests.ps1",
            "dbatools.Tests.ps1",
            "InModule.Commands.Tests.ps1",
            "InModule.Help.Tests.ps1"
        )

        $parseErrorFiles = @()
        $paramBlockFiles = @()
        $topLevelFiles = @()
        $noUnitTestFiles = @()
        $loopBuiltTests = @()
        $unbalancedEnableException = @()
        $discardedComparisons = @()
        $forEachNotFromDiscovery = @()
        $stringSkips = @()
        $quotedCommandNames = @()
        $oldInstanceNames = @()
        $backtickContinuations = @()
        $plainSplats = @()
        $missingEnableException = @()
        $mocksWithoutModuleName = @()
        $integrationWithoutCleanup = @()
        $tempWithoutRandom = @()
        $underscoreVariables = @()
        $bareSkips = @()

        $testFiles = Get-ChildItem -Path "$ModulePath\tests\*.Tests.ps1" | Sort-Object -Property Name

        foreach ($testFile in $testFiles) {
            $isCommandTest = $testFile.Name -notin $notACommandTest
            # Get-DbaFoo.Tests.ps1 tests Get-DbaFoo, and so does the supplementary
            # Get-DbaFoo.Something.Tests.ps1 - which is why the command name is the first segment.
            $commandName = $testFile.Name -replace "^([^.]+)(.+)?\.Tests\.ps1$", "`$1"
            $isSupplementary = $testFile.Name -notmatch "^[^.]+\.Tests\.ps1$"

            $tokens = $null
            $errors = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseFile($testFile.FullName, [ref]$tokens, [ref]$errors)
            if ($errors) {
                $parseErrorFiles += "$($testFile.Name): $($errors.Count) parse errors, first at line $($errors[0].Extent.StartLineNumber)"
                continue
            }

            # One walk over the tree rather than one per rule. The walk is what this Describe spends
            # its time on, so the nodes are collected once and then filtered in memory.
            $allNodes = $ast.FindAll({
                    $args[0] -is [System.Management.Automation.Language.CommandAst] -or
                    $args[0] -is [System.Management.Automation.Language.LoopStatementAst]
                }, $true)
            $commandNodes = @($allNodes | Where-Object { $PSItem -is [System.Management.Automation.Language.CommandAst] })
            $loopNodes = @($allNodes | Where-Object { $PSItem -is [System.Management.Automation.Language.LoopStatementAst] })

            $describeNodes = @($commandNodes | Where-Object { $PSItem.CommandElements[0].Value -eq "Describe" })
            $blockNodes = @($commandNodes | Where-Object { $PSItem.CommandElements[0].Value -in "Describe", "Context", "It" })
            $itNodes = @($commandNodes | Where-Object { $PSItem.CommandElements[0].Value -eq "It" })
            $mockNodes = @($commandNodes | Where-Object { $PSItem.CommandElements[0].Value -eq "Mock" })
            $inModuleScopeNodes = @($commandNodes | Where-Object { $PSItem.CommandElements[0].Value -eq "InModuleScope" })
            $beforeDiscoveryNodes = @($commandNodes | Where-Object { $PSItem.CommandElements[0].Value -eq "BeforeDiscovery" })

            # Returns every tag of a block, handling -Tag and its alias -Tags, the -Tag:Value form,
            # and both a single value and an array literal. Reading only "-Tag <bareword>" missed
            # "-Tags IntegrationTests" and "-Tag UnitTests, 'Something'", and a block missed here
            # silently skipped the checks below instead of running them.
            $tagsOf = {
                param($CommandAst)
                $elements = $CommandAst.CommandElements
                for ($i = 0; $i -lt $elements.Count; $i++) {
                    if ($elements[$i] -isnot [System.Management.Automation.Language.CommandParameterAst]) { continue }
                    if ($elements[$i].ParameterName -notin "Tag", "Tags") { continue }
                    # -Tag:Value binds the value to the parameter itself, -Tag Value puts it next
                    $value = $elements[$i].Argument
                    if (-not $value -and $i -lt $elements.Count - 1) { $value = $elements[$i + 1] }
                    if ($value -is [System.Management.Automation.Language.ArrayLiteralAst]) {
                        return @($value.Elements.Value)
                    }
                    return @($value.Value)
                }
            }

            $unitTestBlocks = @($describeNodes | Where-Object { "UnitTests" -in (& $tagsOf $PSItem) })
            $integrationTestBlocks = @($describeNodes | Where-Object { "IntegrationTests" -in (& $tagsOf $PSItem) })

            if ($isCommandTest) {
                $paramBlockParameters = $ast.ParamBlock.Parameters
                $paramNames = $paramBlockParameters.Name.VariablePath.UserPath
                $declaredCommandName = ($paramBlockParameters | Where-Object { $PSItem.Name.VariablePath.UserPath -eq "CommandName" }).DefaultValue.Value
                $declaredModuleName = ($paramBlockParameters | Where-Object { $PSItem.Name.VariablePath.UserPath -eq "ModuleName" }).DefaultValue.Value
                $declaredDefaults = ($paramBlockParameters | Where-Object { $PSItem.Name.VariablePath.UserPath -eq "PSDefaultParameterValues" }).DefaultValue.Extent.Text
                # A supplementary file may name either the command or its own basename, both of
                # which are unambiguous - Connect-DbaInstance.WindowsSspi.Tests.ps1 tests
                # Connect-DbaInstance, appveyor.watchdog.Tests.ps1 tests appveyor.watchdog.
                $allowedCommandNames = @($commandName, ($testFile.Name -replace "\.Tests\.ps1$", ""))
                if ($paramBlockParameters.Count -ne 3 -or
                    "ModuleName" -notin $paramNames -or
                    "CommandName" -notin $paramNames -or
                    "PSDefaultParameterValues" -notin $paramNames -or
                    $declaredModuleName -ne "dbatools" -or
                    $declaredCommandName -notin $allowedCommandNames -or
                    $declaredDefaults -ne "`$TestConfig.Defaults") {
                    $paramBlockFiles += $testFile.Name
                }

                # No dot sourcing: a private function does not need it, because a checkout has no
                # dbatools.dat and the psm1 then exports every function, private ones included.
                $allowedTopLevel = @("Describe", "InModuleScope", "BeforeDiscovery")
                $topLevelStatements = $ast.EndBlock.Statements
                $notACommand = @($topLevelStatements | Where-Object { $PSItem.PipelineElements[0] -isnot [System.Management.Automation.Language.CommandAst] })
                # Note the ForEach-Object: the CommandElements of all statements flatten into a
                # single list, so indexing [0] into that returns the first element of the first
                # command and nothing else, and a top level Write-Host passes.
                $topLevelNames = $topLevelStatements.PipelineElements |
                    Where-Object { $PSItem -is [System.Management.Automation.Language.CommandAst] } |
                    ForEach-Object { $PSItem.CommandElements[0].Value }
                $otherCommands = @($topLevelNames | Where-Object { $PSItem -notin $allowedTopLevel })
                if ($notACommand -or $otherCommands) {
                    $topLevelFiles += "$($testFile.Name): $(@($notACommand).Count) statements that are not commands, $(@($otherCommands | Sort-Object -Unique) -join ", ")"
                }

                # A supplementary file adds integration coverage to a command whose unit tests live
                # in its own file, so it does not need a UnitTests Describe of its own.
                if (-not $unitTestBlocks -and -not $isSupplementary) {
                    $noUnitTestFiles += $testFile.Name
                }
            }

            # A loop that builds test blocks runs while Pester discovers the tests, and its variables
            # no longer exist when the bodies run. The generated tests are either missing entirely or
            # assert nothing, and in both cases the test report looks healthy. InModule.Help.Tests.ps1
            # was the one file this had to be relaxed for, and it produced zero tests for years - it
            # is fixed now, so the check applies to every file again.
            foreach ($loop in $loopNodes) {
                $blocksInLoop = @($blockNodes | Where-Object {
                        $PSItem.Extent.StartOffset -ge $loop.Extent.StartOffset -and
                        $PSItem.Extent.EndOffset -le $loop.Extent.EndOffset
                    })
                if ($blocksInLoop) {
                    $loopBuiltTests += "$($testFile.Name):$($loop.Extent.StartLineNumber)"
                }
            }

            # A statement inside an It that computes a comparison and throws the result away. It
            # reads like an assertion, it runs, and it can never fail. Only comparisons are flagged,
            # a bare method call is usually a deliberate side effect.
            foreach ($itNode in $itNodes) {
                $body = $itNode.CommandElements | Where-Object { $PSItem -is [System.Management.Automation.Language.ScriptBlockExpressionAst] } | Select-Object -First 1
                if (-not $body) { continue }
                foreach ($statement in $body.ScriptBlock.EndBlock.Statements) {
                    if ($statement -isnot [System.Management.Automation.Language.PipelineAst]) { continue }
                    if ($statement.PipelineElements.Count -ne 1) { continue }
                    $element = $statement.PipelineElements[0]
                    if ($element -isnot [System.Management.Automation.Language.CommandExpressionAst]) { continue }
                    if ($element.Expression -is [System.Management.Automation.Language.BinaryExpressionAst]) {
                        $discardedComparisons += "$($testFile.Name):$($statement.Extent.StartLineNumber): $($statement.Extent.Text)"
                    }
                }
            }

            # -ForEach is read at discovery, so its cases have to be built in a BeforeDiscovery. Fed
            # from a BeforeAll the variable is still empty at discovery and the block produces no
            # tests at all - the same failure as a foreach loop around It, spelled differently.
            $discoveryVariables = @()
            foreach ($beforeDiscovery in $beforeDiscoveryNodes) {
                $discoveryVariables += $beforeDiscovery.FindAll({ $args[0] -is [System.Management.Automation.Language.AssignmentStatementAst] }, $true) |
                    ForEach-Object { $PSItem.Left.Extent.Text.TrimStart("`$") }
            }
            foreach ($block in $blockNodes) {
                $elements = $block.CommandElements
                for ($i = 0; $i -lt $elements.Count; $i++) {
                    if ($elements[$i] -isnot [System.Management.Automation.Language.CommandParameterAst]) { continue }
                    if ($elements[$i].ParameterName -ne "ForEach") { continue }
                    $value = $elements[$i].Argument
                    if (-not $value -and $i -lt $elements.Count - 1) { $value = $elements[$i + 1] }
                    if ($value -is [System.Management.Automation.Language.VariableExpressionAst] -and $value.VariablePath.UserPath -notin $discoveryVariables) {
                        $forEachNotFromDiscovery += "$($testFile.Name):$($block.Extent.StartLineNumber): $($block.CommandElements[0].Value) $($block.CommandElements[1].Extent.Text)"
                    }
                }
            }

            # Blocks switched off with a bare -Skip, so no condition can ever switch them back on.
            # Not wrong in itself, but nothing makes it visible afterwards, and Update-DbaInstance
            # hid 69 unit tests behind one for two years.
            foreach ($block in $blockNodes) {
                $bareSkip = $block.CommandElements | Where-Object {
                    $PSItem -is [System.Management.Automation.Language.CommandParameterAst] -and
                    $PSItem.ParameterName -eq "Skip" -and -not $PSItem.Argument
                }
                if ($bareSkip) {
                    $bareSkips += "$($testFile.Name):$($block.Extent.StartLineNumber): $($block.CommandElements[0].Value) $($block.CommandElements[1].Extent.Text)"
                }
            }

            # A Mock without -ModuleName does not apply to the code inside the module, so the command
            # under test runs unmocked while the test looks like it is isolated. Only mocks inside an
            # InModuleScope are already in the right scope.
            foreach ($mockNode in $mockNodes) {
                $hasModuleName = $mockNode.CommandElements | Where-Object {
                    $PSItem -is [System.Management.Automation.Language.CommandParameterAst] -and $PSItem.ParameterName -eq "ModuleName"
                }
                if ($hasModuleName) { continue }
                $insideInModuleScope = $inModuleScopeNodes | Where-Object {
                    $mockNode.Extent.StartOffset -ge $PSItem.Extent.StartOffset -and
                    $mockNode.Extent.EndOffset -le $PSItem.Extent.EndOffset
                }
                if (-not $insideInModuleScope) {
                    $mocksWithoutModuleName += "$($testFile.Name):$($mockNode.Extent.StartLineNumber)"
                }
            }

            # An integration Describe that creates objects on the instance but has no AfterAll
            # anywhere. A heuristic - some of these clean up in a way this cannot see - so it is a
            # Goal and only reports.
            foreach ($describeNode in $integrationTestBlocks) {
                if ($describeNode.Extent.Text -match "New-Dba|Backup-Dba|New-Item" -and $describeNode.Extent.Text -notmatch "AfterAll") {
                    $integrationWithoutCleanup += "$($testFile.Name):$($describeNode.Extent.StartLineNumber)"
                }
            }

            $content = Get-Content -Path $testFile.FullName

            # The setup of the integration tests has to run with EnableException so that the test
            # fails loudly if the setup fails, instead of testing against a broken state. Where the
            # two statements are placed is deliberately not tested - both of these are in use:
            #   BeforeAll { enable ... remove } and AfterAll { enable ... }
            #   BeforeAll { enable ... }        and AfterAll { ... remove }
            # What always has to hold is that every enable is matched by a remove, because
            # $PSDefaultParameterValues is the object from $TestConfig.Defaults and an enable left
            # behind carries into whatever runs next in the same session.
            $enableCount = ($content -match [regex]::Escape("`$PSDefaultParameterValues[`"*-Dba*:EnableException`"] = `$true")).Count
            $removeCount = ($content -match [regex]::Escape("`$PSDefaultParameterValues.Remove(`"*-Dba*:EnableException`")")).Count
            if ($integrationTestBlocks) {
                if ($enableCount -ne $removeCount) {
                    $unbalancedEnableException += "$($testFile.Name): $enableCount enabled, $removeCount removed"
                }
                if ($enableCount -eq 0) {
                    $missingEnableException += $testFile.Name
                }
            }

            # Every one of these is wrapped in @() because -match against $null returns the boolean
            # $false rather than an empty array, and $false is not empty - the check would then fail
            # on every file instead of none.
            if (@($content -match "-Skip:\s*`"(true|false)`"")) {
                $stringSkips += $testFile.Name
            }
            # The dollar signs below are escaped twice on purpose: once for PowerShell, so that the
            # string is not expanded, and once for the regex, where a bare $ is the end of line
            # anchor and would make the pattern match nothing.
            if (@($content -match "^\s*(Describe|Context)\s+`"\`$CommandName`"")) {
                $quotedCommandNames += $testFile.Name
            }
            if (@($content -match "\`$TestConfig\.instance[123]\b")) {
                $oldInstanceNames += $testFile.Name
            }
            if (@($content -match "``\s*`$")) {
                $backtickContinuations += $testFile.Name
            }
            if (@($content -match "^\s*\`$splat\s*=")) {
                $plainSplats += $testFile.Name
            }
            if (@($content -match "\`$_\.")) {
                $underscoreVariables += $testFile.Name
            }
            if (@($content -match [regex]::Escape("`$TestConfig.Temp")) -and -not @($content -match "Get-Random")) {
                $tempWithoutRandom += $testFile.Name
            }
        }
    }

    It "every test file can be parsed" {
        $parseErrorFiles | Should -BeNullOrEmpty
    }

    It "every test file has the expected param block" {
        $paramBlockFiles | Should -BeNullOrEmpty -Because "the header in tests\CLAUDE.md is mandatory"
    }

    It "every test file has only Describe, InModuleScope and BeforeDiscovery at the top level" {
        $topLevelFiles | Should -BeNullOrEmpty
    }

    It "every test file has at least one Describe block for the unit tests" {
        $noUnitTestFiles | Should -BeNullOrEmpty
    }

    It "no test file builds test blocks in a loop" {
        $loopBuiltTests | Should -BeNullOrEmpty -Because "a loop around It runs at discovery and its variables are gone when the body runs - use -ForEach with cases from BeforeDiscovery"
    }

    It "no It block computes a comparison and throws it away" {
        $discardedComparisons | Should -BeNullOrEmpty -Because "an assertion has to be piped to Should, otherwise it runs and can never fail"
    }

    It "every -ForEach case list is built in a BeforeDiscovery" {
        $forEachNotFromDiscovery | Should -BeNullOrEmpty -Because "-ForEach is read at discovery, so a case list built in BeforeAll is still empty and the block produces no tests"
    }

    It "every EnableException that is set is removed again" {
        $unbalancedEnableException | Should -BeNullOrEmpty -Because "an enable left behind carries into whatever runs next in the same session"
    }

    It "no test file uses a string for -Skip" {
        $stringSkips | Should -BeNullOrEmpty -Because "a non-empty string is always true, so -Skip:`"false`" skips the test"
    }

    It "no test file quotes the command name" {
        $quotedCommandNames | Should -BeNullOrEmpty -Because "Describe `$CommandName does not need quoting"
    }

    It "no test file uses the retired TestConfig instance names" {
        $oldInstanceNames | Should -BeNullOrEmpty -Because "instance1, instance2 and instance3 no longer exist, see the instance table in tests\CLAUDE.md"
    }

    It "no test file uses backtick line continuation" {
        $backtickContinuations | Should -BeNullOrEmpty -Because "backticks are banned, use splatting or a natural line break"
    }

    It "every splat is named after its purpose" {
        $plainSplats | Should -BeNullOrEmpty -Because "a plain `$splat collides across scopes, the guide asks for `$splat<Purpose>"
    }

    It "every integration test enables EnableException for its setup" -Tag Goal -Skip:(-not $includeGoals) {
        $missingEnableException | Should -BeNullOrEmpty
    }

    It "every Mock outside of InModuleScope uses ModuleName" -Tag Goal -Skip:(-not $includeGoals) {
        $mocksWithoutModuleName | Should -BeNullOrEmpty -Because "a Mock without -ModuleName never applies to the code inside the module"
    }

    It "every integration test that creates objects cleans up after itself" -Tag Goal -Skip:(-not $includeGoals) {
        $integrationWithoutCleanup | Should -BeNullOrEmpty -Because "a Describe that creates objects on the instance needs an AfterAll that removes them"
    }

    It "every temporary path is made unique with Get-Random" -Tag Goal -Skip:(-not $includeGoals) {
        $tempWithoutRandom | Should -BeNullOrEmpty -Because "two test files sharing a temp path collide when they run in the same lab"
    }

    It "every test file uses PSItem rather than the underscore variable" -Tag Goal -Skip:(-not $includeGoals) {
        $underscoreVariables | Should -BeNullOrEmpty -Because "the guide asks for `$PSItem except where compatibility needs `$_"
    }

    It "no block is switched off with a bare -Skip" -Tag Goal -Skip:(-not $includeGoals) {
        $bareSkips | Should -BeNullOrEmpty -Because "a block skipped without a condition can never run again"
    }
}

Describe "$ModuleName command structure" -Tag Compliance {
    <#
    The command invariants in CLAUDE.md that the AST can prove, checked over public\ and
    private\functions\. Rule 1: a Stop-Function that can continue has a loop or switch to continue in
    the same function or scriptblock. Rule 3: a begin block that can set the interrupt flag is followed
    by if (Test-FunctionInterrupt) { return } as the first statement of process. The analyzer is in
    dbatools.CommandStructure.ps1, its own fixtures are in the next Describe.
    #>
    BeforeAll {
        $ModulePath = Split-Path $PSScriptRoot -Parent
        . "$PSScriptRoot\dbatools.CommandStructure.ps1"
        $stopFunctionParameter = Get-DbaStopFunctionParameterMap -Path "$ModulePath\private\functions\flowcontrol\Stop-Function.ps1"

        # Helpers whose continue is meant to bind at run time to a loop of the command that calls them.
        # Every call site sits inside a loop of that command, so the continue skips one item and does
        # not escape the command (triaged in #10638). Each entry names the exact number of sites: a new
        # site in the same helper, or one that is gone, fails the check until the entry is updated.
        $dynamicContinueExceptions = @(
            [PSCustomObject]@{
                File     = "Backup-DbaDbCertificate.ps1"
                Function = "export-cert"
                Sites    = 3
                Reason   = "called only inside the foreach over the certificates"
            },
            [PSCustomObject]@{
                File     = "Copy-DbaSsisCatalog.ps1"
                Function = "Invoke-ProjectDeployment"
                Sites    = 2
                Reason   = "called only inside the loops over the projects"
            },
            [PSCustomObject]@{
                File     = "Get-DbaAgentJobHistory.ps1"
                Function = "Get-JobHistory"
                Sites    = 1
                Reason   = "all three call sites sit inside loops of the command"
            },
            [PSCustomObject]@{
                File     = "Get-DbaHelp.ps1"
                Function = "Get-DbaHelp"
                Sites    = 1
                Reason   = "private; its only caller, Find-DbaCommand, runs it inside the foreach over all commands"
            },
            [PSCustomObject]@{
                File     = "Import-DbaCsv.ps1"
                Function = "New-SqlTable"
                Sites    = 1
                Reason   = "called only inside the loop over the files"
            },
            [PSCustomObject]@{
                File     = "Import-DbaCsv.ps1"
                Function = "New-SqlTableWithInferredSchema"
                Sites    = 1
                Reason   = "called only inside the loop over the files"
            },
            [PSCustomObject]@{
                File     = "Import-DbaParquet.ps1"
                Function = "New-SqlTable"
                Sites    = 1
                Reason   = "called only inside the loop over the files"
            },
            [PSCustomObject]@{
                File     = "Import-DbaPfDataCollectorSetTemplate.ps1"
                Function = "Import-DbaPfDataCollectorSetTemplate"
                Sites    = 1
                Reason   = "in the scriptblock that is invoked inside the loops over the computers and the files"
            },
            [PSCustomObject]@{
                File     = "Invoke-DbaPfRelog.ps1"
                Function = "Invoke-DbaPfRelog"
                Sites    = 9
                Reason   = "in the relog scriptblock that is invoked once per file inside the foreach; documented at the sites (#10643)"
            },
            [PSCustomObject]@{
                File     = "Measure-DbaDiskSpaceRequirement.ps1"
                Function = "Get-MountPointFromPath"
                Sites    = 1
                Reason   = "called only inside the loop over the rows"
            },
            [PSCustomObject]@{
                File     = "Measure-DbaDiskSpaceRequirement.ps1"
                Function = "Get-MountPointFromDefaultPath"
                Sites    = 2
                Reason   = "called only inside the loop over the rows"
            }
        )

        $parseErrorFiles = @()
        $functionFiles = Get-ChildItem -Path "$ModulePath\public", "$ModulePath\private\functions" -Filter "*.ps1" -Recurse | Sort-Object -Property Name
        $allFindings = foreach ($functionFile in $functionFiles) {
            $parseErrors = $null
            $functionAst = [System.Management.Automation.Language.Parser]::ParseFile($functionFile.FullName, [ref]$null, [ref]$parseErrors)
            if ($parseErrors) {
                $parseErrorFiles += "$($functionFile.Name): $($parseErrors.Count) parse errors, first at line $($parseErrors[0].Extent.StartLineNumber)"
                continue
            }
            Get-DbaCommandStructureFinding -Ast $functionAst -File $functionFile.Name -StopFunctionParameter $stopFunctionParameter
        }

        $formatFinding = {
            param($Finding)
            "$($Finding.File):$($Finding.Line) $($Finding.Function) - $($Finding.Message)"
        }

        $argumentFindings = @($allFindings | Where-Object Rule -eq "Arguments" | ForEach-Object { & $formatFinding $PSItem })
        $guardFindings = @($allFindings | Where-Object Rule -eq "3" | ForEach-Object { & $formatFinding $PSItem })

        $continueFindings = @()
        $ruleOneFindings = @($allFindings | Where-Object Rule -eq "1")
        foreach ($helperGroup in ($ruleOneFindings | Group-Object -Property File, Function)) {
            $firstFinding = $helperGroup.Group[0]
            $exception = $dynamicContinueExceptions | Where-Object { $PSItem.File -eq $firstFinding.File -and $PSItem.Function -eq $firstFinding.Function }
            if (-not $exception) {
                $continueFindings += $helperGroup.Group | ForEach-Object { & $formatFinding $PSItem }
            } elseif ($exception.Sites -ne $helperGroup.Count) {
                $continueFindings += "$($firstFinding.File) $($firstFinding.Function) - $($helperGroup.Count) dynamic continue sites, the exception list expects $($exception.Sites) (lines $($helperGroup.Group.Line -join ", "))"
            }
        }
        foreach ($exception in $dynamicContinueExceptions) {
            $matchingFindings = @($ruleOneFindings | Where-Object { $PSItem.File -eq $exception.File -and $PSItem.Function -eq $exception.Function })
            if (-not $matchingFindings) {
                $continueFindings += "$($exception.File) $($exception.Function) - the exception list expects $($exception.Sites) dynamic continue sites and there are none, remove the entry"
            }
        }
    }

    It "every command file can be parsed" {
        $parseErrorFiles | Should -BeNullOrEmpty
    }

    It "every Stop-Function call binds its parameters" {
        $argumentFindings | Should -BeNullOrEmpty -Because "a parameter that binds to nothing fails the call, and a switch the check cannot read cannot be checked"
    }

    It "every Stop-Function that can continue has a loop or switch to continue in the same function" {
        $continueFindings | Should -BeNullOrEmpty -Because "without a local target the continue leaves the command and skips an item of the loop of the caller, or ends the whole calling script when a label matches nothing (CLAUDE.md, rule 1)"
    }

    It "every begin block that can set the interrupt flag is followed by the process guard" {
        $guardFindings | Should -BeNullOrEmpty -Because "without the guard process runs on after begin stopped (CLAUDE.md, rule 3)"
    }
}

Describe "$ModuleName command structure analyzer" -Tag Compliance {
    <#
    Fixtures for Get-DbaCommandStructureFinding: each case is a small function, parsed and checked the
    same way as the commands, so a change to the analyzer that stops catching a case, or starts
    reporting a correct one, fails here rather than silently in the command structure Describe.
    #>
    BeforeAll {
        $ModulePath = Split-Path $PSScriptRoot -Parent
        . "$PSScriptRoot\dbatools.CommandStructure.ps1"
        $stopFunctionParameter = Get-DbaStopFunctionParameterMap -Path "$ModulePath\private\functions\flowcontrol\Stop-Function.ps1"

        $findingsOf = {
            param($Code, $Rule)
            $fixtureAst = [System.Management.Automation.Language.Parser]::ParseInput($Code, [ref]$null, [ref]$null)
            @(Get-DbaCommandStructureFinding -Ast $fixtureAst -File "fixture.ps1" -StopFunctionParameter $stopFunctionParameter | Where-Object Rule -eq $Rule)
        }
    }

    Context "Rule 1, a local target for continue" {
        It "reports -Continue without a loop, with the line and function" {
            $code = @'
function Get-Fixture {
    process {
        Stop-Function -Message "x" -Continue
    }
}
'@
            $findings = & $findingsOf $code "1"
            $findings | Should -HaveCount 1
            $findings[0].Line | Should -Be 3
            $findings[0].Function | Should -Be "Get-Fixture"
        }

        It "accepts -Continue inside a foreach, a while and a switch" {
            $code = @'
function Get-Fixture {
    process {
        foreach ($item in $InputObject) { Stop-Function -Message "x" -Continue }
        while ($true) { Stop-Function -Message "x" -Continue }
        switch ($InputObject) { default { Stop-Function -Message "x" -Continue } }
    }
}
'@
            & $findingsOf $code "1" | Should -BeNullOrEmpty
        }

        It "reports -SilentlyContinue alone, which continues under EnableException" {
            $code = @'
function Get-Fixture {
    process {
        Stop-Function -Message "x" -SilentlyContinue
    }
}
'@
            & $findingsOf $code "1" | Should -HaveCount 1
        }

        It "accepts -Continue:`$false and reports -Continue:`$variable" {
            $code = @'
function Get-Fixture {
    process {
        Stop-Function -Message "x" -Continue:$false
        Stop-Function -Message "x" -Continue:$shouldContinue
    }
}
'@
            $findings = & $findingsOf $code "1"
            $findings | Should -HaveCount 1
            $findings[0].Line | Should -Be 4
        }

        It "reads the switches from a splat assigned in the same function" {
            $code = @'
function Get-Fixture {
    process {
        $splatStop = @{
            Message  = "x"
            Continue = $true
        }
        Stop-Function @splatStop
        $splatQuiet = @{
            Message  = "x"
            Continue = $false
        }
        Stop-Function @splatQuiet
    }
}
'@
            $findings = & $findingsOf $code "1"
            $findings | Should -HaveCount 1
            $findings[0].Line | Should -Be 7
        }

        It "reports a splat it cannot resolve, both as unresolved and as a possible continue" {
            $code = @'
function Get-Fixture {
    param($SplatFromCaller)
    process {
        Stop-Function @SplatFromCaller
    }
}
'@
            & $findingsOf $code "Arguments" | Should -HaveCount 1
            & $findingsOf $code "1" | Should -HaveCount 1
        }

        It "accepts a label that names an enclosing loop and reports one that does not" {
            $code = @'
function Get-Fixture {
    process {
        :main foreach ($instance in $SqlInstance) {
            foreach ($database in $Database) {
                Stop-Function -Message "x" -Continue -ContinueLabel main
                Stop-Function -Message "x" -Continue -ContinueLabel other
            }
        }
    }
}
'@
            $findings = & $findingsOf $code "1"
            $findings | Should -HaveCount 1
            $findings[0].Line | Should -Be 6
        }

        It "reports a label that cannot be read statically" {
            $code = @'
function Get-Fixture {
    process {
        :main foreach ($instance in $SqlInstance) {
            Stop-Function -Message "x" -Continue -ContinueLabel $labelName
        }
    }
}
'@
            & $findingsOf $code "1" | Should -HaveCount 1
        }

        It "reports a nested helper even when a loop surrounds its definition or its call" {
            $code = @'
function Get-Fixture {
    process {
        foreach ($item in $InputObject) {
            function Invoke-Helper {
                Stop-Function -Message "x" -Continue
            }
            Invoke-Helper
        }
    }
}
'@
            $findings = & $findingsOf $code "1"
            $findings | Should -HaveCount 1
            $findings[0].Function | Should -Be "Invoke-Helper"
        }

        It "reports a callback that relies on a loop outside it, and accepts one with its own loop" {
            $code = @'
function Get-Fixture {
    process {
        foreach ($item in $InputObject) {
            $item | ForEach-Object { Stop-Function -Message "x" -Continue }
            $item | ForEach-Object { foreach ($part in $PSItem) { Stop-Function -Message "x" -Continue } }
        }
    }
}
'@
            $findings = & $findingsOf $code "1"
            $findings | Should -HaveCount 1
            $findings[0].Line | Should -Be 4
        }

        It "resolves aliases and unique prefixes and reports a parameter that binds to nothing" {
            $code = @'
function Get-Fixture {
    process {
        foreach ($item in $InputObject) {
            Stop-Function -Message "x" -InnerErrorRecord $PSItem -Continue
            Stop-Function -Message "x" -Error $PSItem -Continue
            Stop-Function -Message "x" -ErroRecord $PSItem -Continue
        }
        Stop-Function -Message "x" -Silent
    }
}
'@
            $argumentFindings = & $findingsOf $code "Arguments"
            $argumentFindings | Should -HaveCount 1
            $argumentFindings[0].Line | Should -Be 6
            $continueFindings = & $findingsOf $code "1"
            $continueFindings | Should -HaveCount 1
            $continueFindings[0].Line | Should -Be 8
        }

        It "reads -EnableException as a value, so the next argument is not taken for a switch" {
            $code = @'
function Get-Fixture {
    process {
        Stop-Function -Message "x" -EnableException $true
        return
    }
}
'@
            & $findingsOf $code "1" | Should -BeNullOrEmpty
            & $findingsOf $code "Arguments" | Should -BeNullOrEmpty
        }

        It "matches parameter names without regard to case" {
            $code = @'
function Get-Fixture {
    process {
        stop-function -message "x" -continue
    }
}
'@
            & $findingsOf $code "Arguments" | Should -BeNullOrEmpty
            & $findingsOf $code "1" | Should -HaveCount 1
        }
    }

    Context "Rule 3, the process guard after a begin block that can stop" {
        It "accepts a begin stop followed by the guard as the first statement of process" {
            $code = @'
function Get-Fixture {
    begin {
        Stop-Function -Message "x"
        return
    }
    process {
        if (Test-FunctionInterrupt) { return }
        "work"
    }
}
'@
            & $findingsOf $code "3" | Should -BeNullOrEmpty
        }

        It "reports a missing guard" {
            $code = @'
function Get-Fixture {
    begin {
        Stop-Function -Message "x"
        return
    }
    process {
        "work"
    }
}
'@
            $findings = & $findingsOf $code "3"
            $findings | Should -HaveCount 1
            $findings[0].Line | Should -Be 6
            $findings[0].Message | Should -BeLike "*does not start with*"
        }

        It "reports a guard that is not the first statement" {
            $code = @'
function Get-Fixture {
    begin {
        Stop-Function -Message "x"
    }
    process {
        "work"
        if (Test-FunctionInterrupt) { return }
    }
}
'@
            $findings = & $findingsOf $code "3"
            $findings | Should -HaveCount 1
            $findings[0].Message | Should -BeLike "*not the first statement*"
        }

        It "requires the guard for -SilentlyContinue alone, which sets the flag in the default mode" {
            $code = @'
function Get-Fixture {
    begin {
        Stop-Function -Message "x" -SilentlyContinue
    }
    process {
        "work"
    }
}
'@
            & $findingsOf $code "3" | Should -HaveCount 1
        }

        It "does not require the guard for -Continue, which never sets the flag without throwing" {
            $code = @'
function Get-Fixture {
    begin {
        foreach ($item in $Path) { Stop-Function -Message "x" -Continue }
    }
    process {
        "work"
    }
}
'@
            & $findingsOf $code "3" | Should -BeNullOrEmpty
        }

        It "does not count a helper function or a scriptblock run in a new scope" {
            $code = @'
function Get-Fixture {
    begin {
        function Invoke-Helper { Stop-Function -Message "x" }
        & { Stop-Function -Message "x" }
        Invoke-Command -ScriptBlock { Stop-Function -Message "x" }
    }
    process {
        "work"
    }
}
'@
            & $findingsOf $code "3" | Should -BeNullOrEmpty
        }

        It "counts a dot-sourced scriptblock and a ForEach-Object callback, which run in the command scope" {
            $dotSourced = @'
function Get-Fixture {
    begin {
        . { Stop-Function -Message "x" }
    }
    process {
        "work"
    }
}
'@
            $callback = @'
function Get-Fixture {
    begin {
        $Path | ForEach-Object { Stop-Function -Message "x" }
    }
    process {
        "work"
    }
}
'@
            & $findingsOf $dotSourced "3" | Should -HaveCount 1
            & $findingsOf $callback "3" | Should -HaveCount 1
        }

        It "reports a scriptblock it cannot place for review instead of treating it as safe" {
            $code = @'
function Get-Fixture {
    begin {
        $null = Register-EngineEvent -SourceIdentifier Fixture -Action { Stop-Function -Message "x" }
    }
    process {
        if (Test-FunctionInterrupt) { return }
    }
}
'@
            $findings = & $findingsOf $code "3"
            $findings | Should -HaveCount 1
            $findings[0].Message | Should -BeLike "*cannot determine*"
        }

        It "reports a begin block that can stop when there is no process block to guard" {
            $code = @'
function Get-Fixture {
    begin {
        Stop-Function -Message "x"
    }
    end {
        "work"
    }
}
'@
            & $findingsOf $code "3" | Should -HaveCount 1
        }
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
