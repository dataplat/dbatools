# Obtain a reference to the TypeAccelerators type
$TAType = [psobject].Assembly.GetType("System.Management.Automation.TypeAccelerators")

# Define our type aliases
$TypeAliasTable = @{
    DbaInstance              = "Sqlcollaborative.Dbatools.Parameter.DbaInstanceParameter"
    DbaCmConnectionParameter = "Sqlcollaborative.Dbatools.Parameter.DbaCmConnectionParameter"
    DbaInstanceParameter     = "Sqlcollaborative.Dbatools.Parameter.DbaInstanceParameter"
    dbargx                   = "Sqlcollaborative.Dbatools.Utility.RegexHelper"
    dbatime                  = "Sqlcollaborative.Dbatools.Utility.DbaTime"
    dbadatetime              = "Sqlcollaborative.Dbatools.Utility.DbaDateTime"
    dbadate                  = "Sqlcollaborative.Dbatools.Utility.DbaDate"
    dbatimespan              = "Sqlcollaborative.Dbatools.Utility.DbaTimeSpan"
    prettytimespan           = "Sqlcollaborative.Dbatools.Utility.DbaTimeSpanPretty"
    dbasize                  = "Sqlcollaborative.Dbatools.Utility.Size"
    dbavalidate              = "Sqlcollaborative.Dbatools.Utility.Validation"
    DbaMode                  = "Sqlcollaborative.Dbatools.General.ExecutionMode"
    DbaCredential            = "Sqlcollaborative.Dbatools.Parameter.DbaCredentialparameter"
    DbaCredentialParameter   = "Sqlcollaborative.Dbatools.Parameter.DbaCredentialparameter"
}

# Add all type aliases
foreach ($TypeAlias in $TypeAliasTable.Keys) {
    try {
        $TAType::Add($TypeAlias, $TypeAliasTable[$TypeAlias])
    }
    catch {
    }
}
