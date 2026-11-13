// Height/width of each garment in tools/outfit.src.js (the render check compares the page's drawn garments with these).
const fs = require('fs'), vm = require('vm'), c = vm.createContext({});
vm.runInContext(fs.readFileSync(__dirname + '/outfit.src.js', 'utf8') + ';this.R = {}; ["parka", "jacket", "sweater", "tshirt"].forEach(function (t) { var G = ogarm(t, "#fff", false, false); R[t] = (G.hem - G.top) / (2 * G.half); });', c);
console.log(JSON.stringify(c.R));
