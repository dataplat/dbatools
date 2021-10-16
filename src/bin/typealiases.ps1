# Obtain a reference to the TypeAccelerators type
$TAType = [PSObject].Assembly.GetType("System.Management.Automation.TypeAccelerators")

# Define our type aliases
$TypeAliasTable = @{
    DbaInstance              = "Sqlcollaborative.Dbatools.Parameter.DbaInstanceParameter"
    DbaCmConnectionParameter = "Sqlcollaborative.Dbatools.Parameter.DbaCmConnectionParameter"
    DbaInstanceParameter     = "Sqlcollaborative.Dbatools.Parameter.DbaInstanceParameter"
    DbaRgx                   = "Sqlcollaborative.Dbatools.Utility.RegexHelper"
    DbaTime                  = "Sqlcollaborative.Dbatools.Utility.DbaTime"
    DbaDatetime              = "Sqlcollaborative.Dbatools.Utility.DbaDateTime"
    DbaDate                  = "Sqlcollaborative.Dbatools.Utility.DbaDate"
    DbaTimespan              = "Sqlcollaborative.Dbatools.Utility.DbaTimeSpan"
    PrettyTimespan           = "Sqlcollaborative.Dbatools.Utility.DbaTimeSpanPretty"
    DbaSize                  = "Sqlcollaborative.Dbatools.Utility.Size"
    DbaValidate              = "Sqlcollaborative.Dbatools.Utility.Validation"
    DbaMode                  = "Sqlcollaborative.Dbatools.General.ExecutionMode"
    DbaCredential            = "Sqlcollaborative.Dbatools.Parameter.DbaCredentialparameter"
    DbaCredentialParameter   = "Sqlcollaborative.Dbatools.Parameter.DbaCredentialparameter"
    DbaDatabaseSmo           = "SqlCollaborative.Dbatools.Parameter.DbaDatabaseSmoParameter"
    DbaDatabaseSmoParameter  = "SqlCollaborative.Dbatools.Parameter.DbaDatabaseSmoParameter"
    DbaDatabase              = "SqlCollaborative.Dbatools.Parameter.DbaDatabaseParameter"
    DbaDatabaseParameter     = "SqlCollaborative.Dbatools.Parameter.DbaDatabaseParameter"
    DbaValidatePattern       = "Sqlcollaborative.Dbatools.Utility.DbaValidatePatternAttribute"
    DbaValidateScript        = "Sqlcollaborative.Dbatools.Utility.DbaValidateScriptAttribute"
}

# Add all type aliases
foreach ($TypeAlias in $TypeAliasTable.Keys) {
    try {
        $TAType::Add($TypeAlias, $TypeAliasTable[$TypeAlias])
    } catch {
    }
}