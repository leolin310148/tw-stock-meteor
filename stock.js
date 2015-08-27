IndustryCollection = new Mongo.Collection('industry');
StockCollection = new Mongo.Collection('stock');
if (Meteor.isClient) {

    var app = angular.module('StockApp', ['angular-meteor']);

    app.controller("StockCtrl", ['$scope', '$meteor', function ($scope, $meteor) {
        $scope.stocksInSearch = $meteor.collection(function () {
            return StockCollection.find($scope.getReactively('keywordQuery'), {sort: {ch: 1}});
        });
        $scope.$watch('searchStockKeyword', function () {
            if ($scope.searchStockKeyword && $scope.searchStockKeyword.length > 0) {
                $scope.keywordQuery =
                {
                    $or: [
                        {ch: {$regex: new RegExp("^" + $scope.searchStockKeyword)}},
                        {n: {$regex: new RegExp($scope.searchStockKeyword)}}
                    ]
                }
            }
        });

        $scope.getDisplayStockCode = function (stock) {
            return stock.ch.replace(".tw", "");
        }
    }]);

}

if (Meteor.isServer) {
    Meteor.startup(function () {

        Meteor.http.get("http://mis.twse.com.tw/stock/api/getIndustry.jsp", function (err, response) {
            var resObj = JSON.parse(response.content);
            _.forEach(resObj.tse, function (e) {
                var industry = IndustryCollection.findOne({market: 'tse', code: e.code});
                if (industry == undefined) {
                    e.market = 'tse';
                    IndustryCollection.insert(e);
                }

            })
            _.forEach(resObj.otc, function (e) {
                var industry = IndustryCollection.findOne({market: 'otc', code: e.code});
                if (industry == undefined) {
                    e.market = 'otc';
                    IndustryCollection.insert(e);
                }
            })

            IndustryCollection.find({}).forEach(function (industry) {
                Meteor.http.get("http://mis.twse.com.tw/stock/api/getCategory.jsp?ex=" + industry.market + "&i=" + industry.code, function (e, res) {
                    _.forEach(JSON.parse(res.content).msgArray, function (stock) {
                        if (stock.ch.length <= 7) {
                            stock.ch = stock.ch.replace(".tw", "")
                            var stockInDb = StockCollection.findOne({ch: stock.ch});
                            if (stockInDb == undefined) {
                                StockCollection.insert(stock);
                            }
                        }
                    });
                });
            })
        });


    });
}
