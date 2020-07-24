var ExtensionClass = function() {};

ExtensionClass.prototype = {
    run: function(arguments) {
        arguments.completionFunction({
            "title": document.title,
            "url": document.URL
        });
    }
};

var ExtensionPreprocessingJS = new ExtensionClass;
