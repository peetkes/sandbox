'use strict';
declareUpdate();

xdmp.trace("tst-trigger", 'POST-COMMIT');
xdmp.trace("tst-trigger", uri);
xdmp.trace("tst-trigger", cts.doc(uri));
var props = [fn.head(xdmp.unquote('<priority>2</priority>')).root,
             fn.head(xdmp.unquote('<status>harmonized</status>')).root];
xdmp.documentSetProperties(
       uri, props);
xdmp.documentSetMetadata(uri, {'status','harmonized'});
