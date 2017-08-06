
try { [psobject].Assembly.GetType("System.Management.Automation.TypeAccelerators")::add("DbaCmConnectionParameter", "Sqlcollaborative.Dbatools.Parameter.DbaCmConnectionParameter") }
catch { }
try { [psobject].Assembly.GetType("System.Management.Automation.TypeAccelerators")::add("DbaInstanceParameter", "Sqlcollaborative.Dbatools.Parameter.DbaInstanceParameter") }
catch { }
try { [psobject].Assembly.GetType("System.Management.Automation.TypeAccelerators")::add("dbargx", "Sqlcollaborative.Dbatools.Utility.RegexHelper") }
catch { }
try { [psobject].Assembly.GetType("System.Management.Automation.TypeAccelerators")::add("dbatime", "Sqlcollaborative.Dbatools.Utility.DbaTime") }
catch { }
try { [psobject].Assembly.GetType("System.Management.Automation.TypeAccelerators")::add("dbadatetime", "Sqlcollaborative.Dbatools.Utility.DbaDateTime") }
catch { }
try { [psobject].Assembly.GetType("System.Management.Automation.TypeAccelerators")::add("dbadate", "Sqlcollaborative.Dbatools.Utility.DbaDate") }
catch { }
try { [psobject].Assembly.GetType("System.Management.Automation.TypeAccelerators")::add("dbatimespan", "Sqlcollaborative.Dbatools.Utility.DbaTimeSpan") }
catch { }
try { [psobject].Assembly.GetType("System.Management.Automation.TypeAccelerators")::add("prettytimespan", "Sqlcollaborative.Dbatools.Utility.DbaTimeSpanPretty") }
catch { }
try { [psobject].Assembly.GetType("System.Management.Automation.TypeAccelerators")::add("dbasize", "Sqlcollaborative.Dbatools.Utility.Size") }
catch { }
try { [psobject].Assembly.GetType("System.Management.Automation.TypeAccelerators")::add("dbavalidate", "Sqlcollaborative.Dbatools.Utility.Validation") }
catch { }
try { [psobject].Assembly.GetType("System.Management.Automation.TypeAccelerators")::add("DbaMode", "Sqlcollaborative.Dbatools.General.ExecutionMode") }
catch { }
try { [psobject].Assembly.GetType("System.Management.Automation.TypeAccelerators")::add("DbaCredential", "Sqlcollaborative.Dbatools.Parameter.DbaCredentialparameter") }
catch { }
try { [psobject].Assembly.GetType("System.Management.Automation.TypeAccelerators")::add("DbaCredentialParameter", "Sqlcollaborative.Dbatools.Parameter.DbaCredentialparameter") }
catch { }