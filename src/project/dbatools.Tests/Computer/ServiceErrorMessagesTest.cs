using Dataplat.Dbatools.Computer;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace Dataplat.Dbatools.Computer.Test
{
    [TestClass]
    public class ServiceErrorMessagesTest
    {
        [TestMethod]
        public void ReturnedTableCannotChangeLaterLookups()
        {
            string[] first = ServiceErrorMessages.Resolve();
            first[1] = "caller replacement";
            Assert.AreEqual("The request is not supported.", ServiceErrorMessages.Resolve(1)[0]);
            Assert.AreEqual("The request is not supported.", ServiceErrorMessages.Resolve()[1]);
            Assert.AreNotSame(first, ServiceErrorMessages.Resolve());
        }
    }
}
