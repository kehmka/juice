import 'package:juice/juice.dart';

class LoadProductsEvent extends EventBase {
  final String? category;
  LoadProductsEvent({this.category})
      : super(groupsToRebuild: {'products:list', 'products:search'});
}

class SearchProductsEvent extends EventBase {
  final String query;
  SearchProductsEvent({required this.query})
      : super(groupsToRebuild: {'products:list', 'products:search'});
}

class LoadProductDetailEvent extends EventBase {
  final int productId;
  LoadProductDetailEvent({required this.productId})
      : super(groupsToRebuild: {'products:detail'});
}

class LoadMoreProductsEvent extends EventBase {
  LoadMoreProductsEvent()
      : super(groupsToRebuild: {'products:list'});
}

class LoadCategoriesEvent extends EventBase {
  LoadCategoriesEvent() : super(groupsToRebuild: {'products:list'});
}
