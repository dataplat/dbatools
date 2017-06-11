
try { [psobject].Assembly.GetType("System.Management.Automation.TypeAccelerators")::add("DbaCmConnectionParameter", "Sqlcollective.Dbatools.Parameter.DbaCmConnectionParameter") }
catch { }
try { [psobject].Assembly.GetType("System.Management.Automation.TypeAccelerators")::add("DbaInstanceParameter", "Sqlcollective.Dbatools.Parameter.DbaInstanceParameter") }
catch { }
try { [psobject].Assembly.GetType("System.Management.Automation.TypeAccelerators")::add("dbargx", "sqlcollective.dbatools.Utility.RegexHelper") }
catch { }
try { [psobject].Assembly.GetType("System.Management.Automation.TypeAccelerators")::add("dbatime", "sqlcollective.dbatools.Utility.DbaTime") }
catch { }
try { [psobject].Assembly.GetType("System.Management.Automation.TypeAccelerators")::add("dbadatetime", "sqlcollective.dbatools.Utility.DbaDateTime") }
catch { }
try { [psobject].Assembly.GetType("System.Management.Automation.TypeAccelerators")::add("dbadate", "sqlcollective.dbatools.Utility.DbaDate") }
catch { }
try { [psobject].Assembly.GetType("System.Management.Automation.TypeAccelerators")::add("dbatimespan", "sqlcollective.dbatools.Utility.DbaTimeSpan") }
catch { }
try { [psobject].Assembly.GetType("System.Management.Automation.TypeAccelerators")::add("prettytimespan", "sqlcollective.dbatools.Utility.DbaTimeSpanPretty") }
catch { }
try { [psobject].Assembly.GetType("System.Management.Automation.TypeAccelerators")::add("dbasize", "sqlcollective.dbatools.Utility.Size") }
catch { }
try { [psobject].Assembly.GetType("System.Management.Automation.TypeAccelerators")::add("dbavalidate", "Sqlcollective.Dbatools.Utility.Validation") }
catch { }
try { [psobject].Assembly.GetType("System.Management.Automation.TypeAccelerators")::add("DbaMode", "Sqlcollective.Dbatools.General.ExecutionMode") }
catch { }