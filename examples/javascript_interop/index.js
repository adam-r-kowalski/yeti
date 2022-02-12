var drawSquare = function (length) {
    var lengthString = length.toString();
    var child = document.createElement('div');
    var red = Math.floor(Math.random() * 256);
    var green = Math.floor(Math.random() * 256);
    var blue = Math.floor(Math.random() * 256);
    child.style.backgroundColor = "rgb(".concat(red, ", ").concat(green, ", ").concat(blue, ")");
    child.style.width = lengthString;
    child.style.height = lengthString;
    child.style.margin = '10';
    document.body.appendChild(child);
};

var imports = {
   "draw": {
       "square": drawSquare
   }
};

WebAssembly
    .instantiateStreaming(fetch('index.wasm'), imports)
    .then(function (module) {
        var on_load = module.instance.exports.on_load;
        if (typeof on_load === 'function') {
            on_load();
        }
    });
