// Run by Safari (only Safari invokes this — see the comment in
// ShareViewController.extractSharedURL) before handing the share sheet item
// to PlutarShare, per NSExtensionJavaScriptPreprocessingFile in Info.plist.
// Its result — read back on the native side via
// NSExtensionJavaScriptPreprocessingResultsKey — is what lets a Safari share
// be tagged "via Safari" instead of the generic "via Partage" fallback.
var Plutar = function() {};

Plutar.prototype = {
    run: function(arguments) {
        arguments.completionFunction({
            "title": document.title,
            "URL": document.URL
        });
    }
};

var ExtensionPreprocessingJS = new Plutar;
