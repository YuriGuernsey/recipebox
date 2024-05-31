import 'package:flutter/material.dart';
import 'package:recipebox/models/recipe_model.dart';

class Bookmark with ChangeNotifier {
  List bookmarks = [];

  void addBookmark(recipe) {
    bookmarks.add(recipe);
    notifyListeners();
  }

  void removeBookmark(recipe) {
    bookmarks.remove(recipe);
    notifyListeners();
  }

  bool isBookmarked(recipe) {
    // check in the list is recipe id is in any of the bookmarks list Ids 
    bool isTrue = false;
    for (var i = 0; i < bookmarks.length; i++) {
      if (bookmarks[i].id == recipe.id) {
        isTrue = true;
        break;
      }
    }



    return isTrue;
   
  }

  List get getBookmarks => bookmarks;


}