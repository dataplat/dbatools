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
        'PSUseDeclaredVarsMoreThanAssignments'
    )
    Rules        = @{
        PSUseCompatibleSyntax = @{
            Enable        = $true
            TargetVersion = @(
                '3.0',
                '4.0',
                '5.1',
                '6.2'
            )
        }
    }
}

