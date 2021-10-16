@{
    Severity     = @('Error')
    IncludeRules = @(
        'PSUseCompatibleSyntax',
        'PSAvoidUsingCmdletAliases',
        'PSAvoidUsingWriteHost',
        'PSAvoidDefaultValueSwitchParameter',
        'PSReservedCmdletChar',
        'PSReservedParams',
        'PSAvoidUsingUserNameAndPassWordParams',
        'PSAvoidUsingPlaintTextForPassword',
        'PSAvoidUsingWMICmdlet',
        'PSAvoidUsingWriteHost',
        'PSMisleadingBacktick',
        'PSMissingModuleManifestField',
        'PSPossibleIncorrectComparisonWithNull',
        'PSUseApprovedVerbs',
        'PSUseOutputTypeCorrectly',
        'PSShouldProcess',
        'PSUserToExportFieldsInManifest',
        'PSUseSingularNouns',
        'PSAvoidUsingInvokeExpression',
        'PSUseShouldProcessForStateChangingFunctions',
        'PSUseDeclaredVarsMoreThanAssignments',
        'PSUseCore',
        'PSPlaceOpenBrace',
        'PSPlaceCloseBrace',
        'PSUseConsistentWhitespace',
        'PSUseConsistentIndentation',
        'PSAlignAssignmentStatement',
        'PSUseCorrectCasing'

    )
    Rules        = @{
        PSUseCompatibleSyntax      = @{
            Enable        = $true
            TargetVersion = @(
                '3.0',
                '4.0',
                '5.1',
                '6.2'
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
            CheckOpenBrace  = $true
            CheckOpenParen  = $true
            CheckOperator   = $false
            CheckPipe       = $true
            CheckSeparator  = $true
        }

        PSAlignAssignmentStatement = @{
            Enable         = $true
            CheckHashtable = $true
        }

        PSUseCorrectCasing         = @{
            Enable = $true
        }
    }
}
