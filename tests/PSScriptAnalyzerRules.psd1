@{
    Severity     = @('Error', 'Warning', 'Information')
    IncludeRules = @(
        'PSUseCompatibleSyntax',
        'PSAvoidUsingCmdletAliases',
        'PSAvoidDefaultValueSwitchParameter',
        'PSReservedCmdletChar',
        'PSReservedParams',
        'PSAvoidUsingWMICmdlet',
        'PSMisleadingBacktick',
        # The style test in dbatools.Tests.ps1 fails the build on a trailing space, so the profile
        # that is meant to be run before pushing has to report it too.
        'PSAvoidTrailingWhitespace',
        'PSMissingModuleManifestField',
        'PSPossibleIncorrectComparisonWithNull',
        'PSUseApprovedVerbs',
        'PSUseOutputTypeCorrectly',
        'PSUseSingularNouns',
        'PSPlaceOpenBrace',
        'PSPlaceCloseBrace',
        'PSUseConsistentWhitespace',
        'PSUseConsistentIndentation',
        'PSAlignAssignmentStatement'
    )
    Rules        = @{
        PSUseCompatibleSyntax      = @{
            Enable         = $true
            TargetVersions = @(
                '3.0',
                '4.0',
                '5.1',
                '7.4'
            )
        }

        PSPlaceOpenBrace           = @{
            Enable             = $true
            OnSameLine         = $true
            NewLineAfter       = $true
            IgnoreOneLineBlock = $true
        }

        PSPlaceCloseBrace          = @{
            Enable             = $true
            NewLineAfter       = $false
            IgnoreOneLineBlock = $true
            NoEmptyLineBefore  = $false
        }

        PSUseConsistentIndentation = @{
            Enable              = $true
            Kind                = 'space'
            PipelineIndentation = 'IncreaseIndentationForFirstPipeline'
            IndentationSize     = 4
        }

        PSUseConsistentWhitespace  = @{
            Enable          = $true
            CheckInnerBrace = $true
            # CheckOpenBrace reports "Use space before open brace" for every statement that starts
            # with a script block, which is what { Get-DbaFoo } | Should -Throw looks like. Across
            # the test tree it produced 180 findings, 178 of them that idiom, so the rule buried
            # everything else it found. The remaining checks still cover real spacing mistakes.
            CheckOpenBrace  = $false
            CheckOpenParen  = $true
            CheckOperator   = $false
            CheckPipe       = $true
            CheckSeparator  = $true
        }

        PSAlignAssignmentStatement = @{
            Enable         = $true
            CheckHashtable = $true
        }
    }
}