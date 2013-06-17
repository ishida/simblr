// requires jquery-1.10.0.min.js
// requires jquery.lazyload.min.patched.js
var Simblr = window.Simblr || (new function(){
  var self = this;

  this.start = function(q){
    $('#form').submit(function(e){
      window.history.pushState(null, null, location.href);
      return true;
    });
    var h = window.history;
    if (('state' in h) && h.state != null && h.state.indexOf('<!-- result_success -->') == 0){
      this.showResult(true, h.state);
    }else{
      startToUpdateIndicator();
      startToGetResult(q);
    }
  };

  this.reblog = function(href,post_id){
    openReblogWindow(href);
    addReblogCount(post_id);
  };

  this.showResult = function(success,data){
    if(success){
      $('#result_loading').hide();
      $('#result_error').hide();
      $('#result').html(data).fadeIn();
      $('#form_btn').removeAttr('disabled');
      $('#form_input').removeAttr('disabled');
      $('.lazy').lazyload({ threshold: 400, effect: "fadeIn" });
      $('#sidebar').affix({ offset: { top: 200 } });
      if(data.indexOf('<!-- result_success -->') == 0){
        $('#footer').hide();
        $('#form_more').submit(function(e){
          window.history.pushState(null, null, location.href);
          return true;
        });
      }
    }else{
      $('#result_loading').hide();
      $('#result').hide();
      $('#result_error').fadeIn();
      $('#form_btn').removeAttr('disabled');
      $('#form_input').removeAttr('disabled');
      $('#sidebar').affix({ offset: { top: 200 } });
      $('#footer').show();
    }
  };

  var startToUpdateIndicator = function(){
    $('#result_loading').show();
    var LOADING_MSEC = 15000;
    var INTERVAL_MSEC = 100;
    var W_INC =  INTERVAL_MSEC / LOADING_MSEC * 100;
    var w = 0;
    var timer = setInterval(function(){
      w += W_INC;
      $('#result_loading .bar').width(Math.round(w) + '%');
      if(w >= 98) clearInterval(timer);
    }, INTERVAL_MSEC);
  };

  var retrying_count = 0;
  var startToGetResult = function(q){
    var RETRYING_INTERVAL_MSEC = 5000
    var RETRYING_COUNT_MAX = 6
    $.ajax({
      url: 'result/' + q,
      type: 'get',
      cache: false,
      success: function(data){
        if(data.indexOf('<!-- result_waiting -->') == 0){
          if(retrying_count < RETRYING_COUNT_MAX){
            retrying_count++;
            setTimeout(function(){ startToGetResult(q); },
              RETRYING_INTERVAL_MSEC);
          }else{
            self.showResult(false, null);
          }
        }else{
          self.showResult(true, data);
          if(data.indexOf('<!-- result_success -->') == 0){
            window.history.pushState(data, null, location.href)
          }
        }
      },
      error: function(xhr,status,thrown){
        self.showResult(false, null);
      }
    });
  };

  var openReblogWindow = function(href){
    window.open(href, '', 'width=980, height=600, menubar=no, toolbar=no, scrollbars=yes');
  };

  var addReblogCount = function(post_id){
    post_id_elm = $('#' + post_id);
    if(post_id_elm.attr('data-reblog') != null) return;

    var reblog_count_ids = post_id_elm.attr('data-blogs').split(',');
    for(var i = 0, l = reblog_count_ids.length; i < l; i++){
      var e = $('#' + reblog_count_ids[i]);
      var c_str = e.text();
      var c = c_str == '' ? 0 : parseInt(c_str);
      if (c == 0) e.fadeIn(500);
      else e.fadeOut(500,function(){$(this).fadeIn(500)});
      e.text(++c)
    };
    post_id_elm.attr('data-reblog', '1');
  };
}());