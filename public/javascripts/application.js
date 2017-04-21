$(document).ready(function() {
  $("div.message > .error").fadeOut(5000);
  $("div.message > .success").fadeOut(5000);

  $("div.downvote").hover(function() {
    $(this).css("cursor", 'pointer')
  });

  $("div.upvote").hover(function() {
    $(this).css("cursor", 'pointer')
  });

  $("div.upvote").click(function() {
    var this_div = $(this);

    if (this_div.hasClass("selected")) {
      var selection = "remove";
    } else if (this_div.hasClass("unselected")) {
      var selection = "upvote";
    }

    var form=$(this).children("form");
    var request = $.ajax({
          url: form.attr("action"),
          method: form.attr("method"),
          data: { choice: selection }
        });

    if (this_div.hasClass("selected")) {
      var old_class = "selected";
      var new_class = "unselected";
      var score_change = -1;
    } else if (this_div.hasClass("unselected")) {
      var old_class = "unselected";
      var new_class = "selected";
      if (this_div.siblings().hasClass("selected")) {
        var score_change = 2
      } else if (this_div.siblings().hasClass("unselected")) {
        var score_change = 1
      }
    }

    var score_div = this_div.parent().siblings("div.score");
    var score_text = score_div.text();
    var current_score = parseInt(score_text);
    var new_score = current_score + score_change;

    request.fail(function(jqXHR, textStatus, error_thrown) {
      if (jqXHR.status == 401) {
        var error_message = "<p class='ajax error'>Must be logged in to perform this action</p>"
        var message_div = this_div.parents("div.all_contents").siblings("div.message")
        message_div.html(error_message)
        message_div.children("p").fadeOut(5000)
      }
    });

    request.done(function(data, textStatus, jqXHR) {
      if (jqXHR.status == 204) {
        this_div.removeClass(old_class).addClass(new_class)
        this_div.siblings().attr('class','downvote unselected')
        score_div.text(new_score)
      } else if (jqXHR.status == 200) {
        document.location = data;
      }
    });
  });

  $("div.downvote").click(function() {
    var this_div = $(this)

    if (this_div.hasClass("selected")) {
      var selection = "remove";
    } else if (this_div.hasClass("unselected")) {
      var selection = "downvote";
    }

    var form=$(this).children("form")
    var request = $.ajax({
          url: form.attr("action"),
          method: form.attr("method"),
          data: { choice: selection }
      });

    if (this_div.hasClass("selected")) {
      var old_class = "selected";
      var new_class = "unselected";
      var score_change = 1;
    } else if (this_div.hasClass("unselected")) {
      var old_class = "unselected";
      var new_class = "selected";
      if (this_div.siblings().hasClass("selected")) {
        var score_change = -2
      } else if (this_div.siblings().hasClass("unselected")) {
        var score_change = -1
      }
    }

    var score_div = this_div.parent().siblings("div.score");
    var score_text = score_div.text();
    var current_score = parseInt(score_text);
    var new_score = current_score + score_change;

    request.fail(function(jqXHR, textStatus, error_thrown) {
      if (jqXHR.status == 401) {
        var error_message = "<p class='ajax error'>Must be logged in to perform this action</p>"
        var message_div = this_div.parents("div.all_contents").siblings("div.message")
        message_div.html(error_message)
        message_div.children("p").fadeOut(5000)
      }
    });

    request.done(function(data, textStatus, jqXHR) {
      if (jqXHR.status == 204) {
        this_div.removeClass(old_class).addClass(new_class),
        this_div.siblings().attr('class','upvote unselected')
        score_div.text(new_score);
      } else if (jqXHR.status == 200) {
        document.location = data;
      }
    });

  });
});
