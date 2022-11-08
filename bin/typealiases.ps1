# Obtain a reference to the TypeAccelerators type
$TAType = [psobject].Assembly.GetType("System.Management.Automation.TypeAccelerators")

# Define our type aliases
$TypeAliasTable = @{
    DbaInstance              = "Dataplat.Dbatools.Parameter.DbaInstanceParameter"
    DbaCmConnectionParameter = "Dataplat.Dbatools.Parameter.DbaCmConnectionParameter"
    DbaInstanceParameter     = "Dataplat.Dbatools.Parameter.DbaInstanceParameter"
    dbargx                   = "Dataplat.Dbatools.Utility.RegexHelper"
    dbatime                  = "Dataplat.Dbatools.Utility.DbaTime"
    dbadatetime              = "Dataplat.Dbatools.Utility.DbaDateTime"
    dbadate                  = "Dataplat.Dbatools.Utility.DbaDate"
    dbatimespan              = "Dataplat.Dbatools.Utility.DbaTimeSpan"
    prettytimespan           = "Dataplat.Dbatools.Utility.DbaTimeSpanPretty"
    dbasize                  = "Dataplat.Dbatools.Utility.Size"
    dbavalidate              = "Dataplat.Dbatools.Utility.Validation"
    DbaMode                  = "Dataplat.Dbatools.General.ExecutionMode"
    DbaCredential            = "Dataplat.Dbatools.Parameter.DbaCredentialparameter"
    DbaCredentialParameter   = "Dataplat.Dbatools.Parameter.DbaCredentialparameter"
    DbaDatabaseSmo           = "Dataplat.Dbatools.Parameter.DbaDatabaseSmoParameter"
    DbaDatabaseSmoParameter  = "Dataplat.Dbatools.Parameter.DbaDatabaseSmoParameter"
    DbaDatabase              = "Dataplat.Dbatools.Parameter.DbaDatabaseParameter"
    DbaDatabaseParameter     = "Dataplat.Dbatools.Parameter.DbaDatabaseParameter"
    DbaValidatePattern       = "Dataplat.Dbatools.Utility.DbaValidatePatternAttribute"
    DbaValidateScript        = "Dataplat.Dbatools.Utility.DbaValidateScriptAttribute"
}

# Add all type aliases
foreach ($TypeAlias in $TypeAliasTable.Keys) {
    try {
        $TAType::Add($TypeAlias, $TypeAliasTable[$TypeAlias])
    } catch {
    }
}