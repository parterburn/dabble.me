//http://closure-compiler.appspot.com/home

function removeOverlayipb336310() {
  var o = document.getElementById('ovipb336310');
  if (o) {
    o.style.opacity = 0.0;
    o.parentNode.removeChild(document.getElementById('ovipb336310'));
  }
}

if (!document.getElementById('ovipb336310')) {

  var o=document.createElement('div');
  o.setAttribute('id', 'ovipb336310');
  var textStyle =
  "-webkit-text-size-adjust: none; " +
  "font-family: 'HelveticaNeue-Light', 'Helvetica Neue Light', 'Helvetica Neue', Helvetica, Arial, 'Lucida Grande', sans-serif; font-weight: bold; " +
  "line-height: 1.0; letter-spacing: normal; font-variant: normal; font-style: normal;"
  ;
  o.setAttribute('style',
  "position: fixed; z-index: 2147483647; left: 0; top: 0; width: 100%; height: 100%; font-size: 25px; " +
  "opacity: 0.9; -webkit-transition: opacity 0.25s linear; text-align: center; " +
  "padding: 200px 0 0 0; margin: 0; background-color: #333; color: #F2F2F2; " +
  textStyle
  );
  var o1 = document.createElement('span');
  o1.setAttribute('id', 'omipb336310');
  o1.setAttribute('style', textStyle);
  o1.appendChild(document.createTextNode("VidCast "+String.fromCharCode(8594)));
  o.appendChild(o1);
  o1 = document.createElement('div');
  o1.setAttribute('id', 'ocipb336310');
  o1.setAttribute('style', 'cursor:pointer;margin: 35px auto; width: 120px; font-size: 15px; padding: 10px; color: #ccc; background-color: black; border: 1px solid #aaa;');
  o1.setAttribute('onclick', 'removeOverlayipb336310();');
  o1.appendChild(document.createTextNode("Cancel"));
  o.appendChild(o1);
  document.body.appendChild(o);

  Array.prototype.clean = function(deleteValue) {
    for (var i = 0; i < this.length; i++) {
      if (this[i] == deleteValue) {         
        this.splice(i, 1);
        i--;
      }
    }
    return this;
  };

  var pattern = new RegExp("(http(s)?)[A-Za-z0-9%?=&:/._-]*[.]{1}(mp4(?!\.jpg)|webm|ogg)([?]{1}[A-Za-z0-9%?=&:/.-_;-]*)?", "ig");
  var matches = new Array();
  matches = document.documentElement.innerHTML.match(pattern);

  if (window.location.href.indexOf("ted.com") != -1) {
    var ted_pattern = new RegExp("(http)(.){5}(download.ted.com)(.){2}(talks)(.){2}[A-Za-z0-9_?.=&]*(.mp4)[A-Za-z0-9_?.=&]*", "ig");
    var ted_matches = document.documentElement.innerHTML.match(ted_pattern);
    if (ted_matches) { matches = matches.concat(ted_matches) }
  }

  if (window.location.href.indexOf("dailymotion.com") != -1) {
    var dm_html = document.documentElement.innerHTML
    dm_html = unescape(dm_html);
    dm_html = unescape(dm_html);
    dm_matches = dm_html.match(pattern);
    if (dm_matches) { matches = matches.concat(dm_matches) }
  }

  if (window.location.href.indexOf("khanacademy.org") != -1) {
    var khan_pattern = new RegExp("(http(s)?)[A-Za-z0-9%?=&:/._-]*[.]{1}(mp4|webm|ogg)([?/]{1}[A-Za-z0-9%?=&:/.-_;-]*)?(.mp4)", "ig");
    var khan_matches = document.documentElement.innerHTML.match(khan_pattern);
    if (khan_matches) { matches = matches.concat(khan_matches) }
  }

  var priority = new Array();

  if(matches && matches.length > 0){
    for (i = 0; i < matches.length; i++) {
      if (matches[i].indexOf("facebook.com%5C%2F") != -1) {
        var fb_pattern = new RegExp("(http(s)?)[A-Za-z0-9%?=&:\\/._-]*[.]{1}(mp4|webm|ogg)([?]{1}[A-Za-z0-9%?=&:/.-_;-]*)?", "ig");
        var fb_matches = new Array();
        var decoded_match = decodeURIComponent(matches[i]);
        decoded_match = decoded_match.replace(/\\/g, '');
        fb_matches = decoded_match.match(fb_pattern);
        if (fb_matches && fb_matches.length > 0) {
          priority[0]=fb_matches[0];
        } else {
          priority[5]=matches[i];
        }
      } else if (matches[i].indexOf("lookbackvideo") != -1) {
        var fb_pattern = new RegExp("(http(s)?)[A-Za-z0-9%?=&:\\/._-]*[.]{1}(mp4|webm|ogg)([?]{1}[A-Za-z0-9?=&:/.-_;-]*)?", "ig");
        var fb_matches = new Array();
        var decoded_match = decodeURIComponent(matches[i]);
        decoded_match = decoded_match.replace(/\\/g, '');
        fb_matches = decoded_match.match(fb_pattern);
        if (fb_matches && fb_matches.length > 0) {
          priority[0]=fb_matches[0];
        } else {
          priority[5]=matches[i];
        }      
      } else if (matches[i].indexOf("download.ted.com") != -1) {
        priority[0] = matches[i].replace(/\\/g, '');      
      } else if (matches[i].indexOf("1080") != -1) {
        priority[1] = matches[i];
      } else if (matches[i].indexOf("720") != -1) {
        priority[2] = matches[i];
      } else if (matches[i].indexOf("480") != -1) {
        priority[3] = matches[i];
      } else {
        priority[5]=matches[i];
      }
    }

    priority.clean(undefined);
    var match = priority[0];
    if (match.indexOf("phncdn.com")!= -1) { match = match.replace(/&amp;/g,"&"); }
    window.location = "https://dabble.me/cast/?video_link="+encodeURIComponent(match);
  } else {
    document.getElementById('omipb336310').innerHTML = "No MP4, WEBM, or OGG files found on this page";
    setTimeout(function(){removeOverlayipb336310();},1800);
  }
}
