import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:recipebox/state/bookmark.dart';
import 'package:recipebox/utils/api_handler.dart';

import 'models/recipe_model.dart';

void main() {
  runApp(ChangeNotifierProvider(
      create: (context) => Bookmark(),
      child: MyApp(),
    ),);
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: MyHomePage(),
    );
  }
}

class MyHomePage extends StatefulWidget {
  @override
  _MyHomePageState createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  late ApiHandler api;

 late Future<List<Recipe>> data;
  @override
  void initState() {
    super.initState();
    api = ApiHandler(
      Url: 'https://api.mob.co.uk/',
      username: 'mob-api',
      password: '9r7rey5567ce0m7hbt1u',
    );
    data = api.getData('task/recipes.json');
  }

  @override
  Widget build(BuildContext context) {
      final bookmark = Provider.of<Bookmark>(context);
    return Scaffold(
      appBar: AppBar(
        title: Text('RecipeBox'),
        actions: [
          IconButton(
            icon: Icon(Icons.bookmark),
            onPressed: () {
              showModalBottomSheet<void>(
            context: context,
            builder: (BuildContext context) {
              final bookmark = Provider.of<Bookmark>(context);
              return Container(
                height: 200,
                child: ListView.builder(
                  itemCount: bookmark.getBookmarks.length,
                  itemBuilder: (context, index) {
                    return ListTile(
                      title: Text(bookmark.getBookmarks[index].title),
                      trailing: IconButton(
                        icon: Icon(Icons.delete),
                        onPressed: () {
                         
                            bookmark.removeBookmark(bookmark.getBookmarks[index]);
                          
                          },
                      ),
                    );
                  },
                )
              );
            }
              
                
              );
            },
          ),
        ],
      ),
      body: FutureBuilder<List<Recipe>>(
        future: data,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(child: CircularProgressIndicator());
          } else if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          } else {
           
           return GridView.builder(
              padding: EdgeInsets.all(8.0),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 8.0,
                mainAxisSpacing: 16.0,
              ),
              itemCount: snapshot.data!.length,
              itemBuilder: (context, index) {
                final recipe = snapshot.data![index];
                return GridTile(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      return Column(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8.0), // Make images rounded
                            child: Image.network(
                              recipe.imageUrl,
                              fit: BoxFit.cover,
                              height: constraints.maxHeight * 0.6,
                              width: double.infinity,
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.all(8.0),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Text(
                                    recipe.title,
                                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                IconButton(
                                  icon: Icon(bookmark.isBookmarked(recipe) != 1 ? Icons.bookmark_border : Icons.bookmark),
                                  onPressed: () {
                                    bookmark.addBookmark(recipe);
                                  },
                                ),
                              ],
                            ),
                          ),
                          
                        ],
                      );
                    },
                  ),
                );
              },
            );
          }
        },
      ),
    );
  }
}
