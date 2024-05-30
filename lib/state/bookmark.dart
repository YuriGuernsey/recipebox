import 'package:flutter/material.dart';

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
    return bookmarks.contains(recipe);
  }

  List get getBookmarks => bookmarks;


}