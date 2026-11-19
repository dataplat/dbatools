using System;
using System.Collections.Generic;
using System.Linq;
using System.Management.Automation;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace Dataplat.Dbatools.Message.Test
{
    [TestClass]
    public class NativeCallStackTest
    {
        [TestMethod]
        public void MissingPublicApiReturnsEmptyDiagnostics()
        {
            Assert.AreEqual(0, NativeCallStack.CaptureFrames(() => { throw new MissingMethodException("PS3 public API unavailable"); }).Count());
            Assert.AreEqual(0, NativeCallStack.CaptureFrames(() => { throw new TypeLoadException("Public API type unavailable"); }).Count());
        }

        [TestMethod]
        public void UnrelatedCaptureFailureIsNotSilenced()
        {
            var failure = new InvalidOperationException("debugger failure");
            var actual = Assert.ThrowsException<InvalidOperationException>(() => NativeCallStack.CaptureFrames(() => { throw failure; }));
            Assert.AreSame(failure, actual);
        }

        [TestMethod]
        public void AvailableFramesRetainIdentityAndNullBecomesEmpty()
        {
            var frames = new List<CallStackFrame>();
            Assert.AreSame(frames, NativeCallStack.CaptureFrames(() => frames));
            Assert.AreEqual(0, NativeCallStack.CaptureFrames(() => null).Count());
        }
    }
}
